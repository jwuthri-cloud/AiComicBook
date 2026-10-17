"""Pre-record the Listen mode narration with ElevenLabs (through OpenRouter).

Each page is spoken as a few short clips (the opening, one per panel, the takeaway), so the app
can highlight the panel being read and skip page by page. Clips are cached: re-running only
records text that is new or changed. build_content.py then packs them into the app.

  python3 app/tools/make_narration.py --samples            # one short clip per voice, to choose
  python3 app/tools/make_narration.py --voice george       # every page
  python3 app/tools/make_narration.py --voice george --only fellowship-01

Needs OPENROUTER_API_KEY in the repo's .env, and app/Panels/Content/content.json
(run build_content.py once first).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CONTENT = REPO / "app" / "Panels" / "Content" / "content.json"
NARRATION = REPO / "app" / "narration"
ENDPOINT = "https://openrouter.ai/api/v1/audio/speech"
VOICES = ["george", "sarah", "adam", "alice", "bella", "bill", "brian", "callum", "charlie", "chris", "daniel",
          "eric", "harry", "jessica", "laura", "liam", "lily", "matilda", "river", "roger", "will"]
SAMPLE_VOICES = ["george", "brian", "daniel", "will", "sarah", "alice", "jessica", "matilda"]
SAMPLE_TEXT = ("Imagine a student acting differently when a teacher watches. A model may also respond differently "
               "when it recognizes a test. The question is whether training can make that recognition disappear, "
               "or merely stop it being said aloud.")


def api_key() -> str:
    env = REPO / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith(("OPENROUTER_API_KEY=", "OPENROUTE_API_KEY=")):
                return line.split("=", 1)[1].strip().strip('"')
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key:
        sys.exit("OPENROUTER_API_KEY missing: add it to .env")
    return key


# ---------- what gets read (mirrors Listener.segments in the app) ----------

def sentence(s: str) -> str:
    t = s.strip()
    return t if not t or t[-1] in ".!?:" else t + "."


def speakable(s: str) -> str:
    for a, b in [("→", ", then "), ("->", ", then "), ("≈", " about "), (" vs. ", " versus "), (" vs ", " versus "),
                 ("e.g.", "for example"), ("i.e.", "that is"), ("&", " and ")]:
        s = s.replace(a, b)
    return re.sub(r"\s+", " ", s).strip()


def segments(page: dict) -> list[dict]:
    opening = f"Page {page['number']}. {sentence(page['title'])}"
    if page["subtitle"]:
        opening += " " + sentence(page["subtitle"])
    result = [{"panel": None, "text": speakable(opening)}]
    if not page["panels"]:
        result.append({"panel": None, "text": speakable(page["summary"] or "This page is a picture; open the comic to see it.")})
    for i, p in enumerate(page["panels"]):
        text = sentence(p["heading"])
        if p["body"]:
            text += " " + p["body"]
        if p.get("code"):
            text += " The page shows a code example here."
        result.append({"panel": i, "text": speakable(text)})
    if page["footer"]:
        result.append({"panel": None, "text": "Takeaway: " + speakable(sentence(page["footer"]))})
    return result


# ---------- recording ----------

def record(key: str, model: str, voice: str, text: str, dest: Path) -> None:
    body = json.dumps({"model": model, "input": text, "voice": voice, "response_format": "mp3"}).encode()
    for attempt in range(5):
        req = urllib.request.Request(ENDPOINT, data=body, method="POST", headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                audio = r.read()
            if len(audio) < 1000:
                raise RuntimeError(f"suspiciously small audio ({len(audio)} bytes)")
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_suffix(".part")
            tmp.write_bytes(audio)
            tmp.replace(dest)
            return
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:300]
            if e.code in (400, 401, 402, 403, 404):
                raise RuntimeError(f"HTTP {e.code}: {msg}") from None
            wait = 2 ** attempt * 3
            print(f"  HTTP {e.code}, retrying in {wait}s: {msg}", file=sys.stderr)
            time.sleep(wait)
        except (urllib.error.URLError, TimeoutError, RuntimeError) as e:
            wait = 2 ** attempt * 3
            print(f"  {e}, retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"gave up on {dest.name}")


def text_hash(model: str, voice: str, text: str) -> str:
    return hashlib.sha1(f"{model}|{voice}|{text}".encode()).hexdigest()[:12]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--voice", default="george", choices=VOICES)
    parser.add_argument("--model", default="elevenlabs/eleven-v4")
    parser.add_argument("--only", help="page id prefix, e.g. fellowship-01")
    parser.add_argument("--samples", action="store_true", help="record a short sample per voice and stop")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    key = api_key()

    if args.samples:
        out = NARRATION / "samples"
        for voice in SAMPLE_VOICES:
            dest = out / f"{voice}.mp3"
            if not dest.exists():
                record(key, args.model, voice, SAMPLE_TEXT, dest)
            print(dest)
        return

    content = json.loads(CONTENT.read_text())
    pages = [p for c in content["collections"] for b in c["books"] for p in b["pages"]]
    if args.only:
        pages = [p for p in pages if p["id"].startswith(args.only)]

    out = NARRATION / args.voice
    manifest_path = out / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}

    jobs = []
    for page in pages:
        clips = []
        for i, seg in enumerate(segments(page)):
            h = text_hash(args.model, args.voice, seg["text"])
            file = f"{page['id']}/{i:02d}-{h}.mp3"
            clips.append({"panel": seg["panel"], "file": file, "chars": len(seg["text"])})
            if not (out / file).exists():
                jobs.append((seg["text"], out / file))
        manifest[page["id"]] = {"voice": args.voice, "model": args.model, "clips": clips}

    chars = sum(len(t) for t, _ in jobs)
    print(f"{len(pages)} pages, {len(jobs)} clips to record ({chars:,} characters)")
    done = failed = 0
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(record, key, args.model, args.voice, text, dest): dest for text, dest in jobs}
        for future in as_completed(futures):
            try:
                future.result()
                done += 1
            except Exception as e:  # keep going; a re-run picks up what failed
                failed += 1
                print(f"FAILED {futures[future].relative_to(out)}: {e}", file=sys.stderr)
            if (done + failed) % 25 == 0:
                print(f"  {done + failed}/{len(jobs)}")

    # Drop clips whose text changed since an earlier run.
    keep = {c["file"] for entry in manifest.values() for c in entry["clips"]}
    for f in out.rglob("*.mp3"):
        if str(f.relative_to(out)) not in keep:
            f.unlink()
    out.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=1))
    print(f"recorded {done}, failed {failed}. Now run: python3 app/tools/build_content.py")


if __name__ == "__main__":
    main()
