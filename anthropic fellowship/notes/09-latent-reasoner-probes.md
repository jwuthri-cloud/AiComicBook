# Book09: RL against probes in latent reasoners

Four pages turn the supplied proposal into a controlled comparison. No experiment was run for these comics. Budgets ($25k–$45k), proposed months, and week6fallback come from the user's map. The source's 'open' novelty label is not asserted as independently confirmed.

## Primary anchors

- https://arxiv.org/abs/2412.06769 — Coconut, Chain of Continuous Thought: feeding hidden states back as continuous inputs instead of decoding each step to words.
- https://arxiv.org/abs/2502.21074 — CODI, Continuous Chain-of-Thought via Self-Distillation; verbal and latent representations trained together. The book does not repeat performance/compression numbers or claim arbitrary scale availability.
- https://arxiv.org/abs/2608.04928 — out-of-sight CoT monitorability compares verbal/latent modes using hint reliance, a useful bounded target rather than general 'bad intent'.
- https://arxiv.org/abs/2606.12689 — caution that decodability or observed patterns alone do not establish mechanism.
- https://github.com/facebookresearch/coconut — official reproduction code; implementation and release availability must be rechecked before project selection.

## Design choices

Use independently labeled harmless targets, match tasks and capability as far as feasible, freeze probe choices before the final test, compare task-only versus task-plus-alarm-penalty training, report compute and optimization-step trajectories separately, and keep adaptive diagnostic probes separate from headline frozen-probe results. This is proposed methodology, not a confirmed recipe or universal test. Latent reasoning is not portrayed as inherently deceptive. Looped recurrence is an explicitly labeled scope change, not identical to continuous-thought reasoning. Null results establish only the tested conditions.

