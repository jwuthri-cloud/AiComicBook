# Book10: Training introspection that generalizes

Two pages explain completed work that motivates project08. This is not presented as a fresh candidate project.

## Sources

- User-supplied map, project10 and project08, preserved in source/.
- https://alignment.anthropic.com/2026/introspection-adapters/ — official method and limitations, including reports of false positives on base models. A single shared low-rank adapter trained across same-base behavior variants, then tested on unfamiliar variants. No consciousness claim, literal mind reading, or perfect self-report claim.
- https://arxiv.org/abs/2604.16812 — primary paper.
- https://github.com/safety-research/introspection-adapters — primary training/evaluation pipeline.
- https://alignment.anthropic.com/2026/auditbench/ — independent behavior auditing benchmark.

The comics omit the source's50/56 headline to avoid confusing 'correct report at least sometimes' with dependable per-query accuracy. Calibration, abstention, fingerprints and adversarial pressure are explained as research questions/controls, not claims that the paper solved them. Exact prompts are saved under prompts/10-introspection-foundation/.

