# Book 03 — Training-run evaluation toolkit

Source: [supplied project map](../source/fellowship-project-map-2026-10-11.txt), project 3. This is a proposed toolkit, not a completed result.

Primary grounding: [Anthropic persona vectors](https://www.anthropic.com/research/persona-vectors) describes activation patterns used to monitor character-like drift; [Petri](https://www.anthropic.com/research/petri-open-source-auditing) describes automated behavioral auditing and metric limitations; [Olmo 3 paper](https://arxiv.org/abs/2512.13961) and [Ai2 documentation](https://docs.allenai.org/models/olmo/index.html) describe an open training flow and model variants; [Anthropic reward tampering](https://www.anthropic.com/research/reward-tampering) supplies controlled reward-hacking examples.

The proposed design uses saved checkpoints, identical held-out tasks, frozen monitors, positive/negative controls, lead-time and false-alarm metrics, multiple seeds, and confound checks. Activation signals are fallible correlates, not proof of intentions or causal explanation. The supplied map's checkpoint availability, positive-control access, novelty, roughly 40 checkpoints, and $15–30k compute are unverified planning assumptions; recheck before proposing. The plan, stop rule, and toolkit/paper deliverables come from the supplied map. All plotted data are ILLUSTRATIVE.
