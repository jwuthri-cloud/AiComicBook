# Fellowship project mini-books

Create 41 separate educational comic PNGs: three shared field-guide pages, four pages each for projects 01–09, and two pages for completed project 10. Source material is preserved in source/fellowship-project-map-2026-10-11.txt. This is an independent study aid, not an official Anthropic publication.

## Style and teaching

Follow repository README.md and inspect existing artwork. Portrait 2:3, near-black #05090B, ivory #F2EEDF, cyan #16D9EF, violet #AD70DC, lime #A9D52B, amber #F5BE32. Slanted uppercase brush titles, crisp large body lettering, numbered neon panels, friendly silver robot tutor and curious human learner. Each page has 4–10 panels; usually 5–7 with 170–260 words of actual educational content. Use diagrams, a harmless worked example, and clear scientific distinctions. Every page must identify book number and page x/y. Use a short chapter title rather than squeezing the long project title into every header.

Explain like a curious child, then connect the analogy to the actual experiment. Preserve technical substance. Every technical acronym printed on a page must be expanded on that same page in a readable WORD KEY box or first mention. Avoid unnecessary acronyms entirely. AI may be expanded once per book. Describe probes and natural language tools as imperfect measurements, never literal mind readers. Separate model behavior from claims about intention or consciousness. Label all invented data 'ILLUSTRATIVE' and never make proposed experiments look completed.

## Research and scope

Read each assigned project's source, including its caveats. Verify technical mechanisms using primary papers or official research sources via web tools. Record sources and uncertainty in notes/NN-slug.md. The pasted document's 2026 novelty claims, publication summaries, model/tool availability, budget numbers, and mentor-fit names are source claims, not independently established facts. Do not print 'nobody has done this', exact unverified success rates, confirmed employment conditions, or promised mentorship. Use 'proposed question', 'planning estimate from supplied map', and 'recheck literature and tool availability before pitching'. Budgets are compute estimates, not costs of making these comics. Include control groups, held-out evaluation, frozen monitors where relevant, false positives, random seeds, causal attribution limits, success criteria, fallback/stop criteria, and what a null result teaches.

Books 01–09 should cover: question and foundations; experimental setup/mechanism; measurements, confounds and result interpretation; four-month plan, estimated compute, stop/fallback rule and paper/tool deliverable. Project01 can allocate pages2/3 to its two arms while integrating the measurements. Project10 is a completed-work foundation for project08, not a new candidate.

## Artifacts and quality

Use built-in image_gen for every page. Read the imagegen skill. One call per page; save final PNG into assigned book folder as NN-short-title.png. Preserve exact initial and repair prompts under prompts/BOOK-folder/. Save book.json in each folder with title, source project number, status, pages [{number,title,image}] and concise learning objectives. Do not edit another worker's folder or root index. Inspect every generated page, repair material spelling/factual errors or printed art directions. Never print visual direction instructions as teaching copy. Keep text separate from visual notes in prompts. Use generatedImage(result), parse returned generated file path, copy exact returned asset into workspace. No API/CLI fallback without user authorization. Report failures immediately. Deliver actual images, not only prompts or scripts.
