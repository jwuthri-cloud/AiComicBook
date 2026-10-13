# Panels: the comic library as an iOS app

An offline SwiftUI app for reading and watching every collection in this repository: Fellowship Projects (with narrated videos), the AI Safety Atlas, Machine Learning, Algorithm Patterns and Git.

- **Read like a book**: page-curl reader with three modes per page: the original **comic** (double-tap to zoom), **typeset text** with tappable glossary words, and the page's **video** where one exists.
- **Watch**: every narrated clip, playable one by one or a whole book back to back (AirPlay, Picture in Picture, plays with the silent switch on).
- **Smart search**: typo-tolerant, prefix-as-you-type, acronym-aware (RLHF ↔ reinforcement learning from human feedback), everyday-word synonyms ("cheat" → reward hacking, specification gaming) and an on-device meaning-based boost for questions.
- **Glossary**: 324 terms with plain definitions, related terms and every page they appear in. Words of the glossary are highlighted inside the text pages.
- **Quiz**: 711 written questions covering every page (3–4 each, with explanations and a link back to the page) plus generated glossary questions. Daily 10, Review (spaced repetition: missed questions come back until they stick), Word drill, Quick 5, Hard mode, per-collection and per-book quizzes, streaks and mastery rings.
- **Ask (optional, online)**: a study companion powered by the reader's own OpenAI key (stored in the iPhone Keychain, never in the app). It knows the current page — including the comic image when asked from the comic view — finds relevant pages across the library for each question, accepts photos, and links its sources back to the reader.
- **Offline by design**: everything (≈180 MB of compressed pages and clips) ships inside the app. Progress, bookmarks and recent searches stay on the device.
- **Calm theme**: warm paper by day, soft slate by night, never pure white or black. Follows the system or can be fixed in Settings.

## Build

Requirements: Xcode 26+, Python 3 with Pillow, ffmpeg, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
# 1. Gather the comics, text, glossary and videos into app/Panels/Content (gitignored)
python3 app/tools/build_content.py

# 2. Generate the Xcode project
cd app && xcodegen generate

# 3. Open and run
open Panels.xcodeproj
```

To install on your iPhone: select the **Panels** target → *Signing & Capabilities* → choose your Team (a free Apple ID works for personal installs), then pick your phone as the run destination.

Re-run step 1 whenever comics, transcripts, the glossary or videos change; unchanged media is skipped.

## Where things come from

| Source | Used for |
| --- | --- |
| `anthropic fellowship/**`, `ai safety/**` PNGs + `prompts/` | Pages and their exact printed text |
| `ML/`, `LeetCode/`, `SWE/` PNGs + `app/content-src/transcripts-*.json` | Pages and transcribed text |
| `anthropic fellowship/videos/<book>/*.mp4` | Per-page clips (from `make_videos.py`) |
| `app/content-src/glossary.json` | Glossary terms |
| `app/content-src/synonyms.json` | Everyday-word search expansions |
| `app/content-src/quiz-*.json` | Quiz questions (validated and merged by the build script) |

## Debug shortcuts

Debug builds accept `PANELS_SCREEN` to open a screen at launch (handy for screenshots):

```sh
SIMCTL_CHILD_PANELS_SCREEN="reader:ai-safety-04-interpretability:9:text" xcrun simctl launch booted ai.connectly.panels
# also: book:<id>  search:<query>  term:<id>  play:<book id>  quiz[:daily|words|<book id>]  ask  glossary  watch
```

Search ranking can be checked on the Mac without the simulator:

```sh
swiftc -O app/Panels/Model/{Content,ContentStore,TermMatcher,SearchEngine}.swift app/tools/searchcheck/main.swift -o /tmp/searchcheck
/tmp/searchcheck "how can a model cheat on its tests" "slidng window"
```
