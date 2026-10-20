# AI Comic Book

Educational topics turned into illustrated, comic-inspired cheat sheets: a reader should be able to scan a page, understand the central idea, and remember it through diagrams, worked examples, and short visual takeaways.

The existing artwork suggests a **cyberpunk study-guide series**. Each page works as a standalone learning poster, with numbered panels and recurring guide characters. This README captures that direction so a new topic can feel like part of the same collection.

## What is in this project?

The repository contains PNG artwork organized into subject collections:

- **ML/** — research habits, classical ML, deep learning, metrics, loss functions, and LLM internals through system design.
- **LeetCode/** — algorithm patterns illustrated through representative problems.
- **SWE/** — Git, Docker & Kubernetes, design patterns, system design, DevOps and engineering foundations. New pages are rendered from their transcripts with `app/tools/make_cheatsheets.py`.
- **Futurism/** — 35 cards distilled from Redwood Research's [AI Futurism Reading List](https://blog.redwoodresearch.org/p/ai-futurism-reading-list): timelines and takeoff, misalignment and takeover, AI control, governance, deals and power, welfare and better futures. Each page links to its readings.
- **[ai safety/](ai%20safety/README.md)** — 126 illustrated explanations of alignment, training, interpretability, oversight, evaluations, and policy.
- **[anthropic fellowship/](anthropic%20fellowship/index.html)** — a library of multi-page comic books explaining nine proposed research projects, one completed-work foundation, and shared experimental methods.

The style notes below are based on three inspected pages:

| Reference | What it demonstrates |
| --- | --- |
| [Transformer internals](ML/10-transformer-internals-cheat-sheet.png) | A complex mechanism explained through pipelines, tensor diagrams, comparisons, and a final practice panel. |
| [Arrays & hashing](LeetCode/01-arrays-hashing-two-sum-cheat-sheet.png) | Fundamentals followed by a concrete example, a step-by-step trace, pseudocode, and pitfalls. |
| [Git cheat sheet](SWE/02-git-cheat-sheet.png) | Compact reference panels, workflow illustrations, practical cautions, and a memorable closing line. |

## The visual style we want

**Dark, energetic, illustrated, and useful.** Think futuristic field manual with comic-book personality. The characters draw readers in; the diagrams and concise explanations do the teaching.

### Color and atmosphere

- Near-black backgrounds with subtle teal circuitry, faint city lights, or restrained digital texture.
- Warm white or ivory for the main title and primary text.
- Electric cyan as the dominant accent, supported by violet, lime green, and yellow/amber.
- Orange or red for warnings and mistakes.
- Thin colored panel outlines, lightly rounded corners, and occasional angled section-title tabs.
- Restrained glow: crisp text and diagrams must remain easy to read.

Suggested starting palette, interpreted from the references rather than sampled exactly:

| Role | Color |
| --- | --- |
| Background | `#05090B` |
| Primary text | `#F2EEDF` |
| Cyan | `#16D9EF` |
| Violet | `#AD70DC` |
| Lime | `#A9D52B` |
| Amber | `#F5BE32` |
| Warning | `#F16A32` |

Assign accent colors consistently within a page. A concept, object, or process should keep the same color across its diagrams. Color should reinforce labels and symbols, so meaning remains clear without color alone.

### Typography

- **Main title:** oversized, uppercase, slanted brush lettering with slightly rough edges.
- **Section headings:** condensed, energetic comic lettering; numbered and colored to match their panel.
- **Body copy:** compact, high-contrast lettering with enough spacing to stay readable.
- **Code and precise notation:** clean monospace or clear mathematical typesetting.
- **Speech bubbles:** short uppercase reminders, usually one sentence.

Keep expressive lettering in titles and callouts. Long explanations, formulas, and small labels need clarity more than decoration.

### Characters and illustration

- A small, friendly silver robot with a dark faceplate and glowing cyan eyes acts as the tutor.
- An anime/comic-inspired human learner in dark futuristic clothing usually appears on the opposite side of the header.
- The references vary the human's appearance; the shared visual language matters more than reproducing one exact face.
- Use inked outlines, cel shading, metallic highlights, and cyan rim lighting.
- Characters can point at an idea, ask a question, or deliver a mnemonic in a speech bubble.
- Keep most character art around the header, margins, and footer so diagrams have room.

### Layout

- Tall portrait poster. The references vary in proportion; approximately **2:3** is a useful starting point, with a taller canvas when the subject needs it.
- A strong header contains the title, one-line subtitle, and guide characters.
- The body uses a modular grid of numbered panels, typically two or three columns, with wider panels for processes or comparisons.
- Panels contain a mix of diagrams, short lists, tables, worked examples, and callouts.
- A footer delivers one bold, memorable takeaway.
- Reading order must be obvious: left to right, then downward. Keep numbering sequential even when panel sizes vary.

The inspected pages are information-dense. For new pages, start with **6–8 focused panels** and add more only when everything remains readable at the intended viewing size. Split an overloaded topic into a series.

## How the page should teach

Build around one learning objective: **“After reading this page, the reader can explain or do ___.”**

Use this flexible progression:

1. **Introduce the idea.** Give a plain-language definition and explain why it matters.
2. **Show the parts.** Label the components, vocabulary, or inputs and outputs.
3. **Explain the mechanism.** Use arrows, stages, a timeline, or a process diagram.
4. **Work through an example.** Follow one concrete case with consistent labels and values.
5. **Compare useful alternatives.** Show when a distinction changes the reader's decision.
6. **Expose common mistakes.** Explain the misconception and its correction.
7. **Check understanding.** Include a small question, exercise, or “explain it back” prompt.
8. **End with a takeaway.** Write one accurate sentence the reader can remember.

Adapt the structure to the subject. Algorithms benefit from execution traces; science from mechanisms and labeled systems; history from timelines and cause-and-effect diagrams. Every illustration should help explain something.

Keep the voice direct, encouraging, and concise. Use vivid analogies, then connect them to the real concept. Separate an analogy from a literal explanation when readers might confuse the two.

## Reusable brief for a new topic

Fill this in before generating artwork:

```text
Topic:
Intended audience and assumed knowledge:
Learning objective:
Title:
One-line subtitle:
6–8 numbered panels, each with:
  - Heading
  - Exact short copy
  - Diagram or example to illustrate
Key terms and their definitions:
Facts, notation, or sources to verify:
Common misconceptions:
Robot's short teaching line:
Human learner's short question or reaction:
Final takeaway:
Output dimensions and intended viewing size:
```

### Reusable image-generation prompt

Attach the inspected reference images when the image tool supports visual references. Replace every bracketed field and supply the finished panel copy before using this prompt.

```text
Create a polished educational comic-style cheat-sheet poster about [TOPIC]
for [AUDIENCE]. The learning objective is [OBJECTIVE].

Follow the supplied reference images' visual language: near-black background,
subtle futuristic circuitry, warm-white text, electric-cyan panel outlines,
and supporting violet, lime, and amber accents. Use orange/red sparingly for
warnings. Keep glow subtle and all content sharply readable.

Use a tall portrait composition at [DIMENSIONS]. Place a large uppercase,
slanted brush-lettered title at the top: "[TITLE]".
Below it, add the subtitle: "[SUBTITLE]".

Place a friendly silver robot tutor with cyan eyes near the upper left and
an anime/comic-inspired human learner near the upper right. Use inked contours,
cel shading, and cyan rim lighting. Their speech bubbles are short:
Robot: "[ROBOT LINE]"
Learner: "[LEARNER LINE]"

Arrange [PANEL COUNT] numbered educational panels in an orderly modular grid.
Use thin neon borders, colored section headings, clear gutters, and an obvious
left-to-right, top-to-bottom reading order. Give the main process diagram more
space than supporting notes. Keep characters clear of the teaching content.

Render this approved content accurately:
[NUMBERED PANEL HEADINGS, EXACT COPY, AND DIAGRAM DIRECTIONS]

Use labeled diagrams, arrows, comparisons, and one concrete worked example.
Keep object colors and labels consistent across panels. Use clear body text
and precise notation; use monospace for code if the topic requires it.

Finish with a bold footer: "[TAKEAWAY]".

Prioritize correct information, legible text, and useful visual explanations.
Avoid decorative pseudo-text, excessive glow, clutter, irrelevant code,
invented facts, and speech bubbles that repeat entire explanations.
```

## Example adaptation: photosynthesis

This is an illustrative new-topic brief, not an existing image in the repository. It keeps the robot tutor, human learner, neon panels, and visual teaching approach while replacing the computing content with biology.

**Audience:** curious beginners.  
**Objective:** explain how plants use light energy to help build sugars from carbon dioxide and water.  
**Title:** PHOTOSYNTHESIS CHEAT SHEET  
**Subtitle:** Follow the light, water, and carbon.  
**Robot line:** “Light powers the process!”  
**Learner line:** “Where does the carbon come from?”

| Panel | Content and visual direction |
| --- | --- |
| 1. The big picture | Show sunlight reaching a leaf, water entering through roots, carbon dioxide entering the leaf, and oxygen leaving. Label sugar as a product. |
| 2. Inside the leaf | Zoom from leaf to cell to chloroplast. Label thylakoids and stroma as the locations of the next two panels. |
| 3. Capture light energy | Show light-dependent reactions at the thylakoids: light energy helps produce ATP and NADPH; splitting water releases oxygen. |
| 4. Build with carbon | Show the Calvin cycle in the stroma using carbon dioxide, ATP, and NADPH to produce G3P, which can be used to build sugars. |
| 5. Trace the materials | Follow carbon from carbon dioxide into sugar, and oxygen from split water into released oxygen. Use distinct labels and colors for each path. |
| 6. Correct the myths | Explain that soil supplies water and minerals; carbon dioxide supplies the carbon used to build sugars. Plants also perform cellular respiration. |
| 7. Check understanding | Ask: “Where does the carbon in plant sugars come from?” Put the short answer in a small separate callout. |

**Footer:** CAPTURE LIGHT → FIX CARBON → BUILD SUGARS.

Keep the chloroplast diagrams scientifically recognizable. The futuristic styling belongs in the framing and guide characters; arrows and labels should explain the biology accurately.

## Workflow and quality checklist

1. Choose a narrow topic and audience; draft and verify the teaching content first.
2. Write the exact title, panel copy, labels, and takeaway before generating the poster.
3. Map each panel to a useful visual and use the references to maintain the series style.
4. Generate the page, then inspect both the full composition and enlarged text/details.
5. Correct spelling, missing labels, broken formulas, inaccurate diagrams, and ambiguous arrows. If generated text remains unreliable, typeset it separately over the artwork.
6. Check readability at the size readers will actually use. Reduce content or split the page if needed.
7. Save the final PNG in a subject folder using the existing convention: `Subject/01-topic-cheat-sheet.png`.

A finished page should feel like it belongs beside the existing artwork, teach one coherent topic, and reward both a quick scan and a closer read.
