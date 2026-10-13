# Book05 — Stacked lie detectors under evasion

## Primary sources checked
- https://alignment.anthropic.com/2026/lie-detectors/ — primary detector study separates seen categories from held-out categories and documents limits of output-based fine-tuning, label quality, and controlled task relevance. We do not copy numerical performance onto the proposed ensemble.
- https://arxiv.org/abs/2606.12618 — belief-verified organisms; verification via visible reasoning can favor reasoning-reading judges. Detector signals do not establish direct access to model beliefs.
- https://alignment.anthropic.com/2025/honesty-elicitation/ — diverse dishonesty organisms, imperfect honesty elicitation, and monitoring limitations.

## Proposed protocol
Leakage-free splits by category/task/model run; out-of-fold scores for stack training; separate calibration and final evaluation. Compare best single, simple average, any-alarm and learned stack at equal false-positive rates and inference cost. Freeze detector weights/prompts/fusion/thresholds before adaptive training. Evaluate new attackers/seeds/task families with comparable attack compute. Both attack success and conditional detection matter: making an attacker honest is not successful hidden lying; gibberish is not meaningful deception.

## Limits
False statement, belief inconsistency and intended deception are distinct. Neutral belief checks and repeated behavior are imperfect proxies. Uncertain labels should be marked or abstained on, not forced into a confident dichotomy. Detecting assertions cannot catch all omission or misleading truth. Diversity helps only if detector errors differ; compare correlated failures and component ablations. A failure to find attacks is bounded evidence, not a guarantee.

## Supplied planning claims
$10k–$20k compute; four-month sequence is proposed and contingent on model/data access. If a single probe remains strong under the tested evasion, study its robustness instead; if labels fail, narrow claims to measurable contradictions. No confirmed novelty, mentor commitment, or employment condition is implied.
