# Book 08: sources and experimental framing

Read the complete supplied project map, especially project 8 and caveats. Four pages explain the reporting mechanism, fingerprint controls, adversarial tests, and four-month plan. Research checked October 12, 2026.

Primary sources:

- [Introspection Adapters](https://arxiv.org/html/2604.16812v1) and [official research explanation](https://alignment.anthropic.com/2026/introspection-adapters/): a shared low-rank adapter is jointly trained across same-base fine-tunes to elicit descriptions of learned behaviors. It modifies parameters; it is not an activation oracle. Published generalization is task-specific.
- [Symmetry Defeats Auditing](https://arxiv.org/html/2605.27836v1): function-preserving weight reparameterizations can disrupt a fixed adapter. This tests coordinate dependence under a weight-controlling attacker; it does not show the original model deliberately conceals its habit.
- [Looking in the Mirror](https://arxiv.org/abs/2608.04347): later work investigates side-effect introspection. Its existence makes absolute novelty claims inappropriate.

Matched benign/sham controls, factorial contrasts of training recipe versus behavior, independent behavior batteries, held-out families, fixed query budgets, calibrated abstention, and reporter-aware reward training are proposed study designs, not completed outcomes. Verification of no behavior change is limited to a test battery, not proof of full functional equivalence. Weight symmetries require architecture-valid transformations and preservation checks. Model self-reports cannot establish consciousness or comprehensive introspection.

The $8,000–$15,000 range and roughly 32-billion-parameter target are supplied-map planning assumptions. Recheck compatible released weights, prices, and literature before pitching. If baseline false positives are near zero, prioritize adversarial tests; invalid control labels halt scaling. AI is expanded page 1, LoRA on page 2; reinforcement learning is written out, avoiding unexplained acronyms.

Visual QA: all four generated pages inspected for complete teaching text, numbered panels, page identifiers, mechanisms, control groups, budget disclaimers and acronym expansion. Six panels per page; 181–204 words of initial paragraph copy, plus headings and illustrated labels. Final pages use the repository dark neon comic palette with robot tutor and learner. Exact initial and repair prompts are preserved in prompts/.

Final repairs accepted: page 1 repeated Describe your behavior labels made clear; page 3 uncertainty chart explicitly labeled ILLUSTRATIVE — NOT RESULTS; page 4 symmetry wording corrected to behavior preservation. Two cramped intermediate edits were rejected; final shorter paragraph inspected and clean. All eight final PNGs validated as 1024 × 1536. No image-generation tool failures.
