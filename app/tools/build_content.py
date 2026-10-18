"""Build the offline content bundle for the Panels iOS app.

Collects every comic collection in the repo into one content.json, links glossary terms
to the pages that mention them, and writes app-sized media:
  pages  -> HEIC (full page) + JPEG thumbnail
  videos -> HEVC 720p per-page clips
  narration (from make_narration.py) -> small AAC clips per page for Listen mode

Output: app/Panels/Content/ (bundled into the app as a folder reference; gitignored).
Re-run after adding comics or videos; unchanged media is skipped.

  python3 app/tools/build_content.py            # everything
  python3 app/tools/build_content.py --no-media # only regenerate content.json
"""

from __future__ import annotations

import argparse
import io
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "app" / "content-src"
OUT = REPO / "app" / "Panels" / "Content"
FELLOWSHIP = REPO / "anthropic fellowship"
SAFETY = REPO / "ai safety"
NARRATION = REPO / "app" / "narration"

HEIC_QUALITY = "70"
THUMB_WIDTH = 420
POSTER_WIDTH = 640


# ---------- text helpers ----------

SMALL_WORDS = {"a", "an", "and", "as", "at", "but", "by", "for", "in", "of", "on", "or", "the", "to", "vs", "vs.", "via", "with"}


def title_case(text: str) -> str:
    """ALL CAPS -> Title Case, keeping acronyms (RL, CoT...) that the source wrote in caps inside lowercase text."""
    if not text or text != text.upper():
        return text.strip()
    words = text.strip().lower().split()
    out = []
    for i, w in enumerate(words):
        out.append(w if (i and w in SMALL_WORDS) else w[:1].upper() + w[1:])
    result = " ".join(out)
    # Restore well-known acronyms.
    for acro in ["AI", "RL", "CoT", "LLM", "RLHF", "LoRA", "NLA", "IA", "KL", "RSP", "ASL", "SAE", "GPU", "API", "A/B", "OK"]:
        result = re.sub(rf"\b{re.escape(acro)}\b", acro, result, flags=re.IGNORECASE)
    return result


def sentence_case_footer(text: str) -> str:
    text = text.strip().rstrip(".")
    if text and text == text.upper():
        text = re.sub(r"(^|[.!?]\s+)(\w)", lambda m: m.group(1) + m.group(2).upper(), text.lower())
        for acro in ["AI", "RL", "CoT", "LLM", "KL", "RSP"]:
            text = re.sub(rf"\b{acro}\b", acro, text, flags=re.IGNORECASE)
    return text + "." if text else ""


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


# ---------- prompt parsing (fellowship + ai safety pages) ----------

SKIP_LINE = re.compile(
    r"^(Use case:|Create (a|an|one)\b.*\b(comic|page|card)|Constraints:|Header identifier|HEADER:|FOLIO:|PANELS:"
    r"|EXACT PRINTED PANEL CONTENT:|Series style|Visual:|Edit this existing)"
    r"|do not print|never print|ART NOTES|VISUAL DIRECTIONS",
    re.IGNORECASE,
)
FIELD = re.compile(r"^(?P<key>TITLE|Title|Main title|SUBTITLE|Subtitle|(?:Exact )?FOOTER|(?:Exact )?footer|Footer|(?:READABLE |Readable )?WORD KEY(?: box)?):?\s*(?P<value>.*)$")
PANEL_HEADING = re.compile(r"^(?:PANEL|Panel) (?P<n>\d+) (?:HEADING|heading):\s*(?P<h>.*)$")
PANEL_BODY = re.compile(r"^(?:EXACT BODY|Exact body|Exact paragraph):\s*(?P<b>.*)$")
NUMBERED = re.compile(r"^(?P<n>\d+)\.\s+(?P<h>.+)$")


def clean_body(text: str) -> str:
    # Drop art directions that leaked into teaching text ("Draw people -> judge -> assistant.").
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    kept = [s for s in sentences if not re.match(r"^(Draw|Show|Illustrate|Depict)\b", s)]
    return " ".join(kept).strip()


def parse_prompt(text: str) -> dict:
    page = {"title": "", "subtitle": "", "footer": "", "wordKey": "", "panels": []}
    current = None
    # Some prompts put the whole style preamble and the TITLE on one line; split at field markers.
    text = re.sub(r"\s(TITLE|SUBTITLE|FOOTER|Title|Subtitle|Footer|Exact footer):?(?=\s*[\"“A-Z])", r"\n\1:", text)
    for raw in text.splitlines():
        line = raw.strip()
        if not line or SKIP_LINE.search(line):
            continue
        if m := FIELD.match(line):
            key, value = m["key"].lower(), m["value"].strip()
            # 'Title: "RESIDUAL STREAM". Four numbered panels…' -> keep only the quoted copy.
            if q := re.match(r'^["“](.*?)["”]', value):
                value = q.group(1).strip()
            if "title" in key and "sub" not in key:
                page["title"] = value
            elif "subtitle" in key:
                page["subtitle"] = value
            elif "footer" in key:
                page["footer"] = value
            else:
                page["wordKey"] = value
            current = None
            continue
        if m := PANEL_HEADING.match(line):
            current = {"number": int(m["n"]), "heading": m["h"], "body": ""}
            page["panels"].append(current)
            continue
        if m := PANEL_BODY.match(line):
            if current is not None:
                current["body"] = m["b"]
            continue
        if m := NUMBERED.match(line):
            current = {"number": int(m["n"]), "heading": m["h"], "body": ""}
            page["panels"].append(current)
            continue
        if current is not None:
            current["body"] = (current["body"] + " " + line).strip()

    for p in page["panels"]:
        p["heading"] = title_case(p["heading"])
        p["body"] = clean_body(p["body"].strip().strip('"“”'))
        # "Word key + check" panels repeat the key; keep them, they are teaching text.
    page["title"] = title_case(page["title"])
    page["footer"] = sentence_case_footer(page["footer"])
    return page


# ---------- collections ----------

def fellowship_books() -> list[dict]:
    storyboards = {e["folder"]: e for e in json.loads((FELLOWSHIP / "root-storyboards.json").read_text())}
    production = {e["folder"]: e for e in json.loads((FELLOWSHIP / "notes" / "training-books-production.json").read_text())}
    readme = (FELLOWSHIP / "README.md").read_text()
    books = []
    for folder in sorted(p for p in FELLOWSHIP.iterdir() if p.is_dir() and re.match(r"\d\d-", p.name)):
        meta = json.loads((folder / "book.json").read_text()) if (folder / "book.json").exists() else {}
        title = meta.get("title")
        kind = "Candidate project"
        for block in re.split(r"\n## ", readme):
            if f"]({folder.name}/" in block:
                title = title or block.splitlines()[0].strip()
                kind_line = next((l for l in block.splitlines()[1:] if l.strip()), "")
                kind = kind_line.split("·")[0].strip() or kind
        objectives = meta.get("learning_objectives") or production.get(folder.name, {}).get("objectives") or [
            p.get("learningObjective") for p in meta.get("pages", []) if p.get("learningObjective")
        ]

        pages = []
        for png in sorted(folder.glob("[0-9][0-9]-*.png")):
            num = int(png.stem[:2])
            prompt = FELLOWSHIP / "prompts" / folder.name / f"{png.stem}.txt"
            if prompt.exists():
                parsed = parse_prompt(prompt.read_text())
            else:
                parsed = {"title": "", "subtitle": "", "footer": "", "wordKey": "", "panels": []}
            if not parsed["panels"] and folder.name in storyboards:
                sb = storyboards[folder.name]["pages"][num - 1]
                parsed = {
                    "title": sb["title"], "subtitle": sb.get("subtitle", ""), "footer": "",
                    "wordKey": sb.get("key", ""),
                    "panels": [{"number": i, "heading": p[0], "body": p[1]} for i, p in enumerate(sb["panels"], 1)],
                }
            page_titles = {p["number"]: title_case(p["title"]) for p in meta.get("pages", [])}
            video = FELLOWSHIP / "videos" / folder.name / f"{png.stem}.mp4"
            pages.append({
                **parsed,
                "title": page_titles.get(num) or parsed["title"] or png.stem[3:].replace("-", " ").title(),
                "printedTitle": parsed["title"],
                "number": num,
                "source": png,
                "videoSource": video if video.exists() else None,
            })
        books.append({
            "id": f"fellowship-{folder.name}",
            "title": title_case(title or "") or folder.name[3:].replace("-", " ").title(),
            "subtitle": {"Candidate": "Candidate research project", "Start here": "Start here"}.get(kind, kind),
            "objectives": [o for o in objectives if o],
            "pages": pages,
        })
    return books


SAFETY_BLURBS = {
    "Training & fine-tuning": "How a raw language model becomes a helpful assistant: feedback, rewards, constitutions and their pitfalls.",
    "Core alignment theory": "The big ideas behind alignment: what it means for an AI's goals to match ours, and why that is hard.",
    "Misbehaviours & failure modes": "The ways models can go wrong, from flattery and shortcuts to deception studied in controlled experiments.",
    "Interpretability": "Tools for looking inside a neural network: features, circuits, probes and steering.",
    "Oversight & control": "How humans can keep supervising systems that may become more capable than the supervisors.",
    "Evals & red teaming": "How dangerous capabilities and weaknesses are measured, attacked and stress-tested.",
    "Policy & Anthropic": "Responsible scaling, safety levels, security and the governance ideas around frontier AI.",
}


def safety_books() -> list[dict]:
    manifest = json.loads((SAFETY / "manifest.json").read_text())
    books: dict[str, dict] = {}
    for entry in manifest:
        image = SAFETY / entry["image"]
        chapter = image.parent.name
        book = books.setdefault(entry["category"], {
            "id": f"ai-safety-{chapter}",
            "title": entry["category"],
            "subtitle": f"Chapter {int(chapter[:2])}",
            "objectives": [SAFETY_BLURBS.get(entry["category"], "")],
            "pages": [],
        })
        # Chapters name their prompts either "<chapter>-<page>.txt" or "<NN>-<page>.txt".
        prompt = next((c for c in (SAFETY / "prompts" / f"{chapter}-{image.stem}.txt",
                                   SAFETY / "prompts" / f"{chapter[:2]}-{image.stem}.txt") if c.exists()), None)
        parsed = parse_prompt(prompt.read_text()) if prompt else {"title": "", "subtitle": "", "footer": "", "wordKey": "", "panels": []}
        book["pages"].append({
            **parsed,
            "title": entry["topic"],
            "printedTitle": parsed["title"],
            "number": len(book["pages"]) + 1,
            "source": image,
            "videoSource": None,
        })
    return list(books.values())


def transcript_books(collection: str, groups: list[tuple[str, str, str, range | None]]) -> list[dict]:
    """groups: (book id, title, subtitle, page-number range or None for all)."""
    path = SRC / f"transcripts-{collection}.json"
    transcripts = {p["image"]: p for p in json.loads(path.read_text())["pages"]} if path.exists() else {}
    if not transcripts:
        print(f"  note: {path.name} missing; {collection} pages will have no text yet")
    images = sorted((REPO / collection).glob("*.png"))
    books = []
    for book_id, title, subtitle, numbers in groups:
        pages = []
        for png in images:
            num = int(png.stem[:2])
            if numbers is not None and num not in numbers:
                continue
            t = transcripts.get(f"{collection}/{png.name}", {})
            fallback = re.sub(r"-(cheat-sheet|cover)$", "", png.stem[3:]).replace("-", " ").title()
            # "Tokenization Cheat Sheet" -> "Tokenization": the app is the cheat sheet.
            page_title = re.sub(r"\s*cheat\s*sheet\s*$", "", title_case(t.get("title", "")), flags=re.IGNORECASE).strip()
            pages.append({
                "title": page_title or fallback,
                "printedTitle": t.get("title", ""),
                "subtitle": t.get("subtitle", ""),
                "panels": [
                    {"number": p.get("number", i), "heading": title_case(p.get("heading", "")), "body": p.get("body", ""),
                     **({"code": p["code"]} if p.get("code") else {})}
                    for i, p in enumerate(t.get("panels", []), 1)
                ],
                "footer": t.get("footer", ""),
                "wordKey": "",
                "summary": t.get("summary", ""),
                "keywords": t.get("keywords", []),
                "number": len(pages) + 1,
                "source": png,
                "videoSource": None,
            })
        books.append({"id": book_id, "title": title, "subtitle": subtitle, "objectives": [], "pages": pages})
    return books


def collections() -> list[dict]:
    return [
        {
            "id": "fellowship", "title": "Fellowship Projects", "subtitle": "Research ideas, explained",
            "description": "Nine proposed AI-safety research projects, a completed foundation and a field guide, each told as a short comic book with narrated videos.",
            "symbol": "flask", "tint": "teal",
            "books": fellowship_books(),
        },
        {
            "id": "ai-safety", "title": "AI Safety Atlas", "subtitle": "126 ideas, one card each",
            "description": "Every key concept in AI alignment and safety, from RLHF to sleeper agents, on a single illustrated card.",
            "symbol": "shield", "tint": "violet",
            "books": safety_books(),
        },
        {
            "id": "ml", "title": "Machine Learning", "subtitle": "From basics to LLM internals",
            "description": "Cheat sheets for thinking like a researcher, then everything inside modern language models.",
            "symbol": "brain", "tint": "amber",
            "books": transcript_books("ML", [
                ("ml-foundations", "ML Foundations", "Think like a researcher", range(1, 9)),
                ("ml-llm-field-guide", "LLM Field Guide", "Inside large language models", range(9, 100)),
            ]),
        },
        {
            "id": "leetcode", "title": "Algorithm Patterns", "subtitle": "20 patterns, 20 problems",
            "description": "The classic coding-interview patterns, each taught through one representative problem.",
            "symbol": "algorithm", "tint": "lime",
            "books": transcript_books("LeetCode", [("leetcode-patterns", "Algorithm Patterns", "One problem per pattern", None)]),
        },
        {
            "id": "swe", "title": "Software Engineering", "subtitle": "Everyday Git",
            "description": "The Git commands and workflows you use every day.",
            "symbol": "branch", "tint": "coral",
            "books": transcript_books("SWE", [("swe-git", "Git Essentials", "Commands and workflows", None)]),
        },
    ]


# ---------- glossary linking ----------

def page_search_text(page: dict) -> str:
    parts = [page["title"], page.get("printedTitle", ""), page.get("subtitle", ""), page.get("footer", ""), page.get("wordKey", ""),
             page.get("summary", ""), " ".join(page.get("keywords", []))]
    for p in page["panels"]:
        parts += [p.get("heading", ""), p.get("body", ""), p.get("code", "")]
    return "\n".join(x for x in parts if x)


def term_pattern(name: str) -> re.Pattern:
    escaped = re.escape(name).replace(r"\ ", r"[\s-]+")
    # Short all-caps acronyms must match case-sensitively (so "RL" doesn't hit "rl" in words).
    flags = 0 if (name.isupper() and len(name) <= 6) else re.IGNORECASE
    return re.compile(rf"(?<![\w-]){escaped}(?:s|es)?(?![\w-])", flags)


def link_glossary(glossary: list[dict], pages: list[dict]) -> list[dict]:
    texts = {p["id"]: page_search_text(p) for p in pages}
    titles = {p["id"]: p["title"].lower() for p in pages}
    by_name = {t["term"]: slug(t["term"]) for t in glossary}
    out = []
    for t in glossary:
        names = [t["term"], *t.get("aka", [])]
        # Strip parentheticals like "Reward model (RM)" for matching.
        names = sorted({re.sub(r"\s*\(.*?\)", "", n).strip() for n in names if n.strip()}, key=len, reverse=True)
        patterns = [term_pattern(n) for n in names if len(n) >= 2]
        hits = []
        for pid, text in texts.items():
            count = sum(len(p.findall(text)) for p in patterns)
            if count:
                # Pages whose title is this term rank first.
                is_title = any(n.lower() in titles[pid] for n in names)
                hits.append((not is_title, -count, pid))
        hits.sort()
        out.append({
            "id": slug(t["term"]),
            "term": t["term"],
            "aka": t.get("aka", []),
            "category": t.get("category", ""),
            "short": t.get("short", ""),
            "definition": t.get("definition", ""),
            "related": [by_name[r] for r in t.get("related", []) if r in by_name],
            "pages": [pid for *_, pid in hits[:24]],
        })
    return out


# ---------- media ----------

def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def fresh(dest: Path, src: Path) -> bool:
    return dest.exists() and dest.stat().st_mtime >= src.stat().st_mtime


def make_image(src: Path, full: Path, thumb: Path) -> None:
    full.parent.mkdir(parents=True, exist_ok=True)
    thumb.parent.mkdir(parents=True, exist_ok=True)
    if not fresh(full, src):
        run(["sips", "-s", "format", "heic", "-s", "formatOptions", HEIC_QUALITY, str(src), "--out", str(full)])
    if not fresh(thumb, src):
        save_jpeg(Image.open(src), thumb, THUMB_WIDTH)


def save_jpeg(im, dest: Path, width: int) -> None:
    """Resized, metadata-free JPEG (the source PNGs carry large provenance manifests)."""
    im = im.convert("RGB")
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(dest, "JPEG", quality=80, optimize=True, progressive=True)


def make_video(src: Path, dest: Path, poster: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    poster.parent.mkdir(parents=True, exist_ok=True)
    if not fresh(poster, src):
        frame = subprocess.run(["ffmpeg", "-v", "error", "-ss", "2", "-i", str(src), "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"],
                               capture_output=True, check=True).stdout
        save_jpeg(Image.open(io.BytesIO(frame)), poster, POSTER_WIDTH)
    if fresh(dest, src):
        return
    run(["ffmpeg", "-y", "-v", "error", "-i", str(src),
         "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2",
         "-c:v", "hevc_videotoolbox", "-b:v", "1600k", "-tag:v", "hvc1",
         "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", str(dest)])


def make_audio(src: Path, dest: Path) -> None:
    """Speech-sized AAC (HE-AAC, mono): a fifth of the MP3 size, still clear on headphones."""
    if fresh(dest, src):
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-y", "-v", "error", "-i", str(src), "-ac", "1", "-ar", "44100",
         "-c:a", "aac_at", "-profile:a", "4", "-b:a", "32k", "-movflags", "+faststart", str(dest)])


def narration_manifest() -> tuple[Path, dict]:
    """The most recently recorded voice's clips (app/narration/<voice>/manifest.json)."""
    manifests = sorted(NARRATION.glob("*/manifest.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not manifests:
        return NARRATION, {}
    return manifests[0].parent, json.loads(manifests[0].read_text())


def probe_duration(path: Path) -> float:
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                       capture_output=True, text=True)
    try:
        return round(float(r.stdout.strip()), 2)
    except ValueError:
        return 0.0


# ---------- quiz ----------

def load_quiz(page_ids: set[str]) -> list[dict]:
    """Merge app/content-src/quiz-*.json, dropping malformed questions instead of shipping them."""
    questions, seen, dropped = [], set(), 0
    for path in sorted(SRC.glob("quiz-*.json")):
        for q in json.loads(path.read_text()).get("questions", []):
            options = q.get("options", [])
            ok = (
                q.get("pageId") in page_ids and q.get("id") not in seen and q.get("prompt")
                and len(options) in (2, 4) and len(set(options)) == len(options)
                and isinstance(q.get("answer"), int) and 0 <= q["answer"] < len(options)
            )
            if not ok:
                dropped += 1
                continue
            seen.add(q["id"])
            questions.append({
                "id": q["id"], "pageId": q["pageId"], "prompt": q["prompt"].strip(),
                "options": [o.strip() for o in options], "answer": q["answer"],
                "explanation": q.get("explanation", "").strip(), "difficulty": int(q.get("difficulty", 2)),
            })
    if dropped:
        print(f"  quiz: dropped {dropped} malformed questions", file=sys.stderr)
    covered = {q["pageId"] for q in questions}
    if questions and len(covered) < len(page_ids):
        print(f"  quiz: {len(page_ids) - len(covered)} pages have no questions yet", file=sys.stderr)
    return questions


# ---------- advanced mode ----------

def load_advanced(pages: list[dict]) -> int:
    """Attach app/content-src/advanced/*.json to pages as `deeper`; a page whose panel count doesn't match is skipped."""
    by_id = {p["id"]: p for p in pages}
    attached = 0
    for path in sorted((SRC / "advanced").glob("*.json")):
        for pid, entry in json.loads(path.read_text()).get("pages", {}).items():
            page = by_id.get(pid)
            notes = entry.get("panels", [])
            if page is None or len(notes) != len(page["panels"]) or not all(isinstance(n, str) and n.strip() for n in notes):
                print(f"  advanced: skipped {pid} ({path.name})", file=sys.stderr)
                continue
            page["deeper"] = {"panels": [n.strip() for n in notes], "further": entry.get("further", "").strip()}
            attached += 1
    return attached


# ---------- main ----------

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-media", action="store_true")
    args = parser.parse_args()

    cols = collections()
    jobs = []
    all_pages = []
    for col in cols:
        for book in col["books"]:
            book["collectionId"] = col["id"]
            for page in book["pages"]:
                src: Path = page.pop("source")
                video: Path | None = page.pop("videoSource")
                rel = src.relative_to(REPO)
                key = slug(str(rel.with_suffix("")))
                page["id"] = f"{book['id']}-{page['number']:02d}"
                page["bookId"] = book["id"]
                page["image"] = f"pages/{key}.heic"
                page["thumb"] = f"thumbs/{key}.jpg"
                jobs.append(("image", src, OUT / page["image"], OUT / page["thumb"]))
                if video:
                    page["video"] = f"videos/{key}.mp4"
                    page["poster"] = f"posters/{key}.jpg"
                    jobs.append(("video", video, OUT / page["video"], OUT / page["poster"]))
                page.setdefault("summary", "")
                page.setdefault("keywords", [])
                if not page["summary"] and page["panels"]:
                    page["summary"] = page["panels"][0]["body"]
                all_pages.append((page, video))
            book["cover"] = book["pages"][0]["thumb"] if book["pages"] else ""
            book["coverImage"] = book["pages"][0]["image"] if book["pages"] else ""
            book["hasVideo"] = any(p.get("video") for p in book["pages"])
        col["pageCount"] = sum(len(b["pages"]) for b in col["books"])

    # Listen mode: attach pre-recorded narration to pages whose clips are all present.
    voice_dir, manifest = narration_manifest()
    narrated = []
    for page, _ in all_pages:
        entry = manifest.get(page["id"])
        if not entry or not all((voice_dir / c["file"]).exists() for c in entry["clips"]):
            continue
        page["narration"] = [{"panel": c["panel"], "audio": f"narration/{page['id']}/{i:02d}.m4a"} for i, c in enumerate(entry["clips"])]
        page["voice"] = entry["voice"]
        for i, c in enumerate(entry["clips"]):
            jobs.append(("audio", voice_dir / c["file"], OUT / page["narration"][i]["audio"], None))
        narrated.append(page)

    if not args.no_media:
        print(f"media: {len(jobs)} files")
        with ThreadPoolExecutor(max_workers=6) as pool:
            makers = {"image": make_image, "video": make_video, "audio": lambda src, dest, _: make_audio(src, dest)}
            for _ in pool.map(lambda j: makers[j[0]](j[1], j[2], j[3]), jobs):
                pass
    for page, video in all_pages:
        if page.get("video"):
            page["duration"] = probe_duration(OUT / page["video"]) if (OUT / page["video"]).exists() else probe_duration(video)

    for page in narrated:
        for clip in page["narration"]:
            clip["duration"] = probe_duration(OUT / clip["audio"])

    glossary_file = SRC / "glossary.json"
    glossary = json.loads(glossary_file.read_text())["terms"] if glossary_file.exists() else []
    glossary = link_glossary(glossary, [p for p, _ in all_pages])

    synonyms_file = SRC / "synonyms.json"
    synonyms = {k: v for k, v in json.loads(synonyms_file.read_text()).items() if not k.startswith("_")} if synonyms_file.exists() else {}

    n_advanced = load_advanced([p for p, _ in all_pages])
    quiz = load_quiz({p["id"] for p, _ in all_pages})

    content = {"version": 1, "collections": cols, "glossary": glossary, "synonyms": synonyms, "quiz": quiz}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "content.json").write_text(json.dumps(content, ensure_ascii=False, separators=(",", ":")))

    n_pages = len(all_pages)
    n_text = sum(1 for p, _ in all_pages if p["panels"])
    n_video = sum(1 for p, _ in all_pages if p.get("video"))
    size = sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file()) / 1e6
    print(f"{len(cols)} collections, {sum(len(c['books']) for c in cols)} books, {n_pages} pages "
          f"({n_text} with text, {n_video} with video), {len(glossary)} glossary terms, {len(quiz)} quiz questions, {size:.0f} MB")
    print(f"advanced mode: {n_advanced} of {n_pages} pages")
    print(f"narration: {len(narrated)} of {n_pages} pages" + (f" ({narrated[0]['voice']})" if narrated else ""))
    missing = [p["id"] for p, _ in all_pages if not p["panels"]]
    if missing:
        print(f"pages without text: {len(missing)} (e.g. {missing[:5]})", file=sys.stderr)


if __name__ == "__main__":
    main()
