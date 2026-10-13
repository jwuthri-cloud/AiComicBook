"""Turn each fellowship comic book into a series of 10-second explainer videos with Gemini Omni.

One conversation per book folder:
  turn 1 = book context + page 01 image  -> video 01
  turn 2 = page 02 image (same thread)    -> video 02
  ...
Every turn chains on `previous_interaction_id`, so the model keeps the earlier pages
and clips in view and the clips stay visually consistent. Clips are then normalized
and concatenated per book with ffmpeg.

Usage:
  python make_videos.py --dry-run                 # print the prompts, no API calls
  python make_videos.py --books 01 04             # only books whose folder starts with 01 / 04
  python make_videos.py                           # every book
  python make_videos.py --force                   # regenerate clips that already exist
  python make_videos.py --concat-only             # just rebuild the per-book full videos

Needs GEMINI_API_KEY (or GOOGLE_API_KEY) in .env (this folder or repo root) and ffmpeg.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT_DIR = HERE / "videos"
DEFAULT_MODEL = "gemini-omni-1.1-flash"
CLIP_SECONDS = 10
MAX_ATTEMPTS = 3

# Final normalized format every clip is converted to before concatenation.
ASPECTS = {"16:9": (1280, 720), "9:16": (720, 1280)}
FPS = 24
AUDIO_RATE = 48000

# Shared by every book so all clips across the whole series match.
STYLE_BIBLE = """\
You are the director of a short explainer-video series that turns an illustrated comic study guide \
about AI safety research into narrated video. The audience is curious non-experts: smart adults \
or teenagers with no machine-learning background. Every clip must leave them understanding one idea.

SERIES LOOK (identical in every clip, every book):
- Cyberpunk study-guide aesthetic taken from the comic pages: near-black background #05090B with faint \
teal circuitry, warm ivory #F2EEDF highlights, electric cyan #16D9EF as the main accent, violet #AD70DC, \
lime #A9D52B and amber #F5BE32 as secondary accents, orange-red #F16A32 only for warnings or mistakes.
- Clean 2D cel-shaded animation with crisp ink outlines and restrained neon glow, matching the comic art.
- Recurring cast: a small friendly silver robot tutor with glowing cyan eyes (the explainer) and a curious \
human learner in futuristic clothing (asks the questions the viewer would ask). Keep their designs, \
colors and proportions exactly the same in every clip.
- Keep the same visual metaphor for the same concept across the book (if a model is a robot sorting \
blocks on page 1, it stays that robot later).

NARRATION AND SOUND (identical in every clip):
- One calm, warm, clear English narrator voice, the same voice every time, speaking at a relaxed pace.
- Plain words. Use the page's analogy first, then connect it to the real research idea in one sentence. \
If a technical term is needed, define it in the same breath. The narration MUST be completely finished by the 9-second mark: no word may be spoken after 9.0 s, \
and the last sentence must be complete, never cut off. Write it to fit (about 20-22 words).
- Soft ambient synth bed at low volume, same mood every clip. No sudden loud sounds.

CAMERA AND EDITING:
- One continuous, smooth shot or gentle slow push-ins and pans. No fast cuts, no shaky camera.
- Do not invent new on-screen text, numbers, logos or charts with readable labels: generated text is \
often misspelled. Let the narration carry the words; on-screen visuals should be drawings, icons, arrows, \
motion. Short words copied exactly from the comic page are acceptable only if rendered cleanly.
- No Anthropic or other company logos.

CONTINUITY RULES SO CLIPS CAN BE CONCATENATED SEAMLESSLY:
- Exactly {seconds} seconds, {aspect} aspect ratio.
- FIRST ~0.5 s: start from a calm, near-still frame inspired by the supplied comic page.
- LAST ~1 s (9.0-10.0 s): no speech at all; settle into a calm, near-still frame on the dark #05090B circuitry background with the robot \
tutor resting in frame, narration finished, music softly sustained. This shared resting frame is the \
transition point to the next clip.
- Same lighting, palette and character scale from clip to clip.

ACCURACY:
- These are PROPOSED experiments, never completed results. Do not show results as proven. Any numbers on \
the page are illustrative.
- Probes and monitors are imperfect measuring instruments, never literal mind readers. Describe model \
behavior without claiming the model has feelings or intentions.
"""

FIRST_TURN = """\
{style}

=== BOOK CONTEXT ===
Book: {book_title} ({folder})
Status: {status}
This book has {n_pages} pages; you will make one {seconds}-second clip per page, in order, in this \
conversation. Later turns will add the next page.

Learning objectives:
{objectives}

Project write-up from the fellowship project map (background; its "explain it like I'm 5" part is a \
good source of plain-language analogies; do not mention researcher names, budgets or novelty claims):
{project}

Research notes (background for accuracy; do not read these aloud):
{notes}

=== PAGE {num}/{n_pages}: "{page_title}" ===
The attached image is this comic page. Its exact printed teaching text is:
{page_text}

Now generate the {seconds}-second explainer video for page {num}. Pick the single most important idea \
on this page and explain it so a non-expert gets it, using the page's own analogy and characters. \
This is the opening clip of the book, so the narrator may briefly name the book's big question.
"""

NEXT_TURN = """\
=== PAGE {num}/{n_pages}: "{page_title}" ===
The attached image is the next comic page. Its exact printed teaching text is:
{page_text}

Generate the {seconds}-second video for page {num}, continuing the same series: same characters, same \
narrator voice, same palette and music, same opening/closing resting frames. Narration must be fully \
finished by the 9-second mark, with no speech in the last second. Start where the previous \
clip's idea left off and explain the single most important new idea on this page for a non-expert.{closing}
"""

LAST_PAGE_CLOSING = (
    " This is the final clip of the book: end the narration with a one-sentence takeaway that sums up the "
    "whole book."
)


# ---------- context loading ----------

def load_env() -> None:
    for env in (HERE / ".env", HERE.parent / ".env"):
        if not env.exists():
            continue
        for line in env.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip().removeprefix("export ").strip(), value.strip().strip("'\""))


def book_folders(selectors: list[str]) -> list[Path]:
    folders = sorted(p for p in HERE.iterdir() if p.is_dir() and re.match(r"\d\d-", p.name))
    if selectors:
        folders = [f for f in folders if any(f.name.startswith(s) for s in selectors)]
    return folders


def load_pages(folder: Path) -> tuple[dict, list[dict]]:
    """Return (book.json or {}, [{num, title, image}]) for a folder."""
    book_file = folder / "book.json"
    book = json.loads(book_file.read_text()) if book_file.exists() else {}
    pages = book.get("pages") or []
    if pages:
        pages = [{"num": p["number"], "title": p["title"], "image": folder / p["image"]} for p in pages]
    else:
        # Books without book.json (01-03): derive pages from the PNG file names.
        pages = []
        for png in sorted(folder.glob("[0-9][0-9]-*.png")):
            title = png.stem[3:].replace("-", " ").title()
            pages.append({"num": int(png.stem[:2]), "title": title, "image": png})
    return book, pages


def book_title(folder: Path, book: dict) -> str:
    if book.get("title"):
        return book["title"]
    readme = (HERE / "README.md").read_text()
    # README lists books as "## Title" followed by the page links into the folder.
    for block in re.split(r"\n## ", readme):
        if f"]({folder.name}/" in block:
            return block.splitlines()[0].strip()
    return folder.name[3:].replace("-", " ").title()


def page_text(folder: Path, page: dict) -> str:
    """Exact printed text of a page, from its (latest repair) generation prompt or the storyboard."""
    # The original page prompt holds the full printed copy; *-repair.txt files are only small edit requests.
    prompt = HERE / "prompts" / folder.name / f"{page['image'].stem}.txt"
    if prompt.exists():
        # Keep only the printed content: drop the image-style preamble and art directions.
        skip = re.compile(r"^(Use case:|Create |Constraints:)|do not print|never print", re.IGNORECASE)
        lines = [line for line in prompt.read_text().splitlines() if not skip.search(line)]
        return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()

    storyboards = json.loads((HERE / "root-storyboards.json").read_text())
    for entry in storyboards:
        if entry["folder"] == folder.name and len(entry["pages"]) >= page["num"]:
            sb = entry["pages"][page["num"] - 1]
            panels = "\n".join(f"{i}. {p[0].upper()}\n{p[1]}" for i, p in enumerate(sb["panels"], 1))
            return f"Title: {sb['title']}\nSubtitle: {sb.get('subtitle', '')}\nWord key: {sb.get('key', '')}\n{panels}"
    return "(no text on file; read it from the image)"


def project_section(folder: Path) -> str:
    """This book's project write-up from context.txt (the fellowship project map)."""
    context = HERE / "context.txt"
    if not context.exists():
        return "(none)"
    text = context.read_text()
    num = int(folder.name[:2])
    if num == 0:
        # Field guide: the program overview before the first project.
        section = text.split("#1 ·", 1)[0]
    else:
        match = re.search(rf"^#{num} ·.*?(?=^#\d+ ·|^03 · What has been researched)", text, re.S | re.M)
        section = match.group(0) if match else "(none)"
    # Mentor names and scoop warnings are not teaching material.
    drop = re.compile(r"^(Mentor fit|Show this subfield)")
    return "\n".join(line for line in section.splitlines() if not drop.match(line)).strip()


def book_context(folder: Path, book: dict) -> dict:
    objectives = book.get("learning_objectives") or [
        p["learningObjective"] for p in book.get("pages", []) if p.get("learningObjective")
    ]
    readme = folder / "README.md"
    if not objectives and readme.exists():
        objectives = [readme.read_text()[:1200]]
    notes_file = HERE / "notes" / f"{folder.name}.md"
    notes = notes_file.read_text().strip() if notes_file.exists() else "(none)"
    return {
        "book_title": book_title(folder, book),
        "folder": folder.name,
        "status": book.get("status", "Candidate research project"),
        "objectives": "\n".join(f"- {o}" for o in objectives) or "- (see pages)",
        "notes": notes,
        "project": project_section(folder),
    }


# ---------- generation ----------

def image_part(path: Path) -> dict:
    return {"type": "image", "mime_type": "image/png", "data": base64.b64encode(path.read_bytes()).decode()}


def build_turn(page: dict, n_pages: int, ctx: dict | None, folder: Path, aspect: str) -> str:
    common = {
        "num": page["num"], "n_pages": n_pages, "page_title": page["title"],
        "page_text": page_text(folder, page), "seconds": CLIP_SECONDS,
    }
    if ctx is not None:
        style = STYLE_BIBLE.format(seconds=CLIP_SECONDS, aspect=aspect)
        return FIRST_TURN.format(style=style, **ctx, **common)
    closing = LAST_PAGE_CLOSING if page["num"] == n_pages else ""
    return NEXT_TURN.format(closing=closing, **common)


class NoVideoError(RuntimeError):
    pass


def wait_for(client, interaction, timeout: int = 900):
    deadline = time.time() + timeout
    while getattr(interaction, "status", "completed") == "in_progress":
        if time.time() > deadline:
            raise TimeoutError(f"interaction {interaction.id} still in progress after {timeout}s")
        time.sleep(5)
        interaction = client.interactions.get(interaction.id)
    if interaction.status != "completed":
        raise RuntimeError(f"interaction {interaction.id} ended with status {interaction.status}")
    return interaction


def save_video(interaction, dest: Path, api_key: str) -> None:
    """Save the raw model output under raw/, then keep only this page's own clip in dest."""
    video = interaction.output_video
    if video is None:
        raise NoVideoError(f"interaction {interaction.id} returned no video")
    raw = dest.parent / "raw" / dest.name
    raw.parent.mkdir(parents=True, exist_ok=True)
    if video.data:
        raw.write_bytes(base64.b64decode(video.data))
    elif video.uri:
        req = urllib.request.Request(video.uri, headers={"x-goog-api-key": api_key})
        with urllib.request.urlopen(req) as resp:
            raw.write_bytes(resp.read())
    else:
        raise NoVideoError(f"interaction {interaction.id} video has neither data nor uri")
    keep_last_clip(raw, dest)


def keep_last_clip(raw: Path, dest: Path) -> None:
    """Later turns sometimes return every earlier clip of the thread plus the new one; keep the new tail."""
    duration = probe_duration(raw)
    if duration <= CLIP_SECONDS + 0.5:
        dest.write_bytes(raw.read_bytes())
        return
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-ss", f"{duration - CLIP_SECONDS:.3f}", "-i", str(raw),
         "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-c:a", "aac", "-b:a", "192k", str(dest)],
        check=True,
    )


def generate_book(client, folder: Path, args, api_key: str) -> list[Path]:
    book, pages = load_pages(folder)
    ctx = book_context(folder, book)
    out = OUT_DIR / folder.name
    state_file = out / "state.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {"clips": {}}
    print(f"\n=== {folder.name}: {ctx['book_title']} ({len(pages)} pages)")

    previous_id = None
    clips = []
    for i, page in enumerate(pages):
        dest = out / f"{page['image'].stem}.mp4"
        clips.append(dest)
        turn = build_turn(page, len(pages), ctx if i == 0 else None, folder, args.aspect)
        record = state["clips"].get(dest.name)

        if args.dry_run:
            print(f"\n--- turn {i + 1} ({page['image'].name}) ---\n{turn}")
            continue
        if dest.exists() and record and not args.force:
            # Reuse the existing clip but keep the thread going from its interaction.
            print(f"  page {page['num']}: exists, skipping ({dest.name})")
            previous_id = record["interaction_id"]
            continue

        print(f"  page {page['num']}: generating {dest.name} ...", flush=True)
        request = {
            "model": args.model,
            "input": [{"type": "text", "text": turn}, image_part(page["image"])],
        }
        if previous_id:
            request["previous_interaction_id"] = previous_id
        for attempt in range(1, MAX_ATTEMPTS + 1):
            interaction = wait_for(client, client.interactions.create(**request))
            try:
                save_video(interaction, dest, api_key)
                break
            except NoVideoError as exc:
                # The model occasionally answers with only its text plan; asking again usually works.
                if attempt == MAX_ATTEMPTS:
                    raise
                print(f"    {exc}; retrying ({attempt}/{MAX_ATTEMPTS})", flush=True)
        previous_id = interaction.id
        state["clips"][dest.name] = {
            "page": page["num"], "image": str(page["image"].relative_to(HERE)),
            "interaction_id": interaction.id, "duration": probe_duration(dest),
        }
        out.mkdir(parents=True, exist_ok=True)
        state_file.write_text(json.dumps(state, indent=2))
        raw_seconds = probe_duration(out / "raw" / dest.name)
        note = f", trimmed from {raw_seconds:.1f}s" if raw_seconds > CLIP_SECONDS + 0.5 else ""
        print(f"    saved ({state['clips'][dest.name]['duration']:.1f}s{note})")
    return clips


# ---------- ffmpeg ----------

def probe_duration(path: Path) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    try:
        return float(result.stdout.strip())
    except ValueError:
        return 0.0


def has_audio(path: Path) -> bool:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    return bool(result.stdout.strip())


def normalize(src: Path, dest: Path, aspect: str) -> None:
    """Re-encode to one shared size/fps/codec/audio format so the concat is clean."""
    w, h = ASPECTS[aspect]
    vf = f"scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:color=0x05090B,fps={FPS},format=yuv420p,setsar=1"
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src)]
    if not has_audio(src):
        cmd += ["-f", "lavfi", "-i", f"anullsrc=channel_layout=stereo:sample_rate={AUDIO_RATE}", "-shortest"]
    cmd += ["-vf", vf, "-c:v", "libx264", "-preset", "medium", "-crf", "18",
            "-c:a", "aac", "-ar", str(AUDIO_RATE), "-ac", "2", "-b:a", "192k", str(dest)]
    subprocess.run(cmd, check=True)


def concat_book(folder: Path, clips: list[Path], aspect: str) -> None:
    existing = [c for c in clips if c.exists()]
    if len(existing) != len(clips):
        missing = [c.name for c in clips if not c.exists()]
        print(f"  skip concat for {folder.name}: missing {missing}")
        return
    norm_dir = OUT_DIR / folder.name / "normalized"
    norm_dir.mkdir(parents=True, exist_ok=True)
    list_file = norm_dir / "concat.txt"
    lines = []
    for clip in clips:
        norm = norm_dir / clip.name
        normalize(clip, norm, aspect)
        lines.append(f"file '{norm.name}'")
    list_file.write_text("\n".join(lines) + "\n")
    final = OUT_DIR / f"{folder.name}.mp4"
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", str(list_file), "-c", "copy", str(final)],
        check=True,
    )
    print(f"  -> {final} ({probe_duration(final):.1f}s)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--books", nargs="*", default=[], help="folder prefixes, e.g. 00 04 (default: all)")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--aspect", choices=sorted(ASPECTS), default="16:9")
    parser.add_argument("--dry-run", action="store_true", help="print the prompts without calling the API")
    parser.add_argument("--force", action="store_true", help="regenerate clips that already exist")
    parser.add_argument("--concat-only", action="store_true", help="skip generation, only rebuild per-book videos")
    args = parser.parse_args()

    folders = book_folders(args.books)
    if not folders:
        sys.exit(f"no book folders match {args.books}")

    client = api_key = None
    if not args.dry_run and not args.concat_only:
        load_env()
        api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            sys.exit("set GEMINI_API_KEY in .env")
        from google import genai
        client = genai.Client(api_key=api_key)

    failures = []
    for folder in folders:
        if args.concat_only:
            _, pages = load_pages(folder)
            clips = [OUT_DIR / folder.name / f"{p['image'].stem}.mp4" for p in pages]
        else:
            try:
                clips = generate_book(client, folder, args, api_key)
            except Exception as exc:  # keep going with the other books
                print(f"  FAILED {folder.name}: {exc}")
                failures.append(folder.name)
                continue
        if not args.dry_run:
            concat_book(folder, clips, args.aspect)

    if failures:
        sys.exit(f"\nfailed books: {', '.join(failures)} (re-run to resume; finished clips are kept)")


if __name__ == "__main__":
    main()
