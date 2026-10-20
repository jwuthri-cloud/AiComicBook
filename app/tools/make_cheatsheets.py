"""Generate missing cheat-sheet PNGs from their transcripts with OpenAI's image model.

Every page in app/content-src/transcripts-<COL>*.json whose "image" file doesn't exist yet is rendered from its
exact printed copy (title, subtitle, panels, footer) plus the per-panel "diagram" art notes, in the series style
described in README.md. A style reference image is attached so new pages match the existing ones.

  python3 app/tools/make_cheatsheets.py                    # every missing page
  python3 app/tools/make_cheatsheets.py SWE/04-docker...png --force   # (re)render specific pages

Needs OPENAI_API_KEY (read from the environment or the repo's .env).
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "app" / "content-src"
MODEL = os.environ.get("CHEATSHEET_MODEL", "gpt-image-2.5-flare")  # gpt-image-2 renders pages flare's moderation rejects
REFERENCE = REPO / "LeetCode" / "01-arrays-hashing-two-sum-cheat-sheet.png"

STYLE = """Create a finished, polished educational comic-style cheat-sheet poster, portrait 2:3 (1024x1536).
Match the attached reference image's series style exactly (layout language, colors, characters, lettering) but NOT its content:
near-black #05090B background with subtle teal circuitry, ivory #F2EEDF text, electric-cyan #16D9EF panel outlines,
violet #AD70DC, lime #A9D52B and amber #F5BE32 accents, orange-red only for warnings. Restrained glow, crisp text.
Large uppercase slanted brush-lettered title at the top with the subtitle under it. A small friendly silver robot tutor with
glowing cyan eyes in the upper left and an anime/comic-style human learner in dark futuristic clothing in the upper right,
inked contours, cel shading, each with one short speech bubble. Below, numbered panels in an orderly modular grid
(2 columns, wider panels where a diagram needs room), thin neon borders, colored numbered headings, clear gutters,
obvious left-to-right, top-to-bottom reading order. Every panel has a small labeled diagram or worked example.
Code in clean monospace. A bold footer banner with the takeaway at the bottom.
Render ALL supplied text exactly, spelled correctly, large enough to read. Do not add any other text, fake text,
watermarks or production notes. Diagram labels must be short and factual."""


def load_env() -> None:
    env = REPO / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"'))


def prompt_for(page: dict) -> str:
    lines = [STYLE, "", f'TITLE: "{page["title"]}"', f'SUBTITLE: "{page["subtitle"]}"',
             f'ROBOT BUBBLE: "{page.get("robot", "")}"', f'LEARNER BUBBLE: "{page.get("learner", "")}"', "",
             f"{len(page['panels'])} NUMBERED PANELS (exact printed text, then the diagram to draw):"]
    for p in page["panels"]:
        lines.append(f'{p["number"]}. {p["heading"].upper()}')
        lines.append(f'Text: "{p["body"]}"')
        if p.get("code"):
            lines.append(f'Code block (monospace): "{p["code"]}"')
        if p.get("diagram"):
            lines.append(f"Draw (labels only, not this sentence): {p['diagram']}")
    lines += ["", f'FOOTER: "{page["footer"].upper()}"']
    return "\n".join(lines)


def multipart(fields: dict[str, str], files: dict[str, Path]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    out = b""
    for k, v in fields.items():
        out += f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
    for k, path in files.items():
        out += (f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; filename="{path.name}"\r\n'
                f"Content-Type: image/png\r\n\r\n").encode() + path.read_bytes() + b"\r\n"
    return out + f"--{boundary}--\r\n".encode(), f"multipart/form-data; boundary={boundary}"


def render(page: dict, quality: str) -> bytes:
    body, ctype = multipart({"model": MODEL, "prompt": prompt_for(page), "size": "1024x1536", "quality": quality, "n": "1"},
                            {"image[]": REFERENCE})
    for attempt in range(4):
        req = urllib.request.Request("https://api.openai.com/v1/images/edits", data=body, method="POST",
                                     headers={"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}", "Content-Type": ctype})
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return base64.b64decode(json.load(r)["data"][0]["b64_json"])
        except urllib.error.HTTPError as e:
            msg = e.read().decode()[:400]
            if e.code < 500 and e.code != 429:
                raise RuntimeError(f"{e.code}: {msg}") from None
            print(f"  retry {attempt + 1} after {e.code}: {msg}", file=sys.stderr)
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  retry {attempt + 1} after {e}", file=sys.stderr)
        time.sleep(15 * (attempt + 1))
    raise RuntimeError("gave up after retries")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="*", help='e.g. "SWE/04-docker-cheat-sheet.png" (default: every missing page)')
    ap.add_argument("--force", action="store_true", help="re-render even if the PNG exists")
    ap.add_argument("--quality", default="high")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--dry-run", action="store_true", help="print prompts only")
    args = ap.parse_args()
    load_env()

    pages = [p for path in sorted(SRC.glob("transcripts-*.json")) for p in json.loads(path.read_text())["pages"]]
    todo = [p for p in pages if (p["image"] in args.images if args.images else not (REPO / p["image"]).exists())]
    if not args.force:
        todo = [p for p in todo if not (REPO / p["image"]).exists()]
    print(f"{len(todo)} pages to render with {MODEL}")
    if args.dry_run:
        for p in todo:
            print(f"\n===== {p['image']}\n{prompt_for(p)}")
        return

    def one(page: dict) -> None:
        try:
            png = render(page, args.quality)
        except Exception as e:  # keep the batch going; the page is retried on the next run
            print(f"FAILED {page['image']}: {e}", file=sys.stderr)
            return
        (REPO / page["image"]).write_bytes(png)
        print(f"ok {page['image']}")

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(one, todo))


if __name__ == "__main__":
    main()
