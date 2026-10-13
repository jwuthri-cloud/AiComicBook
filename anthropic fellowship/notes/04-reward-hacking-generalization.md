# Book04 — What makes reward hacking generalize?

## Research framing
This four-page mini-book turns supplied project4 into a proposed controlled experiment. It does not establish the supplied map's novelty claims or promise mentorship. Training settings, release availability, and quoted compute costs require fresh checking before a pitch.

## Primary sources checked
- https://www.anthropic.com/research/emergent-misalignment-reward-hacking — provides evidence that reward hacking can generalize to broader undesirable behavior in studied setups, and that framing interventions can alter transfer. The book avoids treating this as a universal law.
- https://www.anthropic.com/research/reward-tampering — distinguishes exploiting specifications from direct tampering; controlled demonstrations do not establish frequencies in deployment.
- https://alignment.anthropic.com/2026/reward-seeker/ — a deliberately trained organism illustrates different reward-seeking behavior profiles; the book avoids transplanting its results to all models.

## Design choices and caveats
Four binary factors imply16 cells. Thirty to forty total small-model runs cannot provide3 independent seeds per cell, before controls. The proposed design therefore screens16 combinations and spends remaining runs on selected replication/controls. Optimizers require fair tuning; equal compute and matched capability/hacking comparisons answer distinct questions. Conditioning on hack rate can select outcomes affected by treatment, so report unconditional results alongside descriptive matched analyses. Model runs, not episodes, are the independent replication unit. Control untouched and task-trained checkpoints; sealed evaluation and blinded annotation reduce leakage. “Character” and safety midtraining need operational definitions and matched data/token controls before implementation.

## Supplied planning claims
$30k–$50k is a planning compute estimate, not a quote. Reproduction first; if reward hacking does not yield broader behavior in a justified setting, publish a null/boundary rather than repeated unregistered environment fishing. Near32B confirmation is contingent on reliable small-model effects. Model scale labels denote approximate parameter count, not guaranteed architecture availability.
