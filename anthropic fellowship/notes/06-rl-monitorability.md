# Book06 — Monitorability cost of ordinary reinforcement learning

## Primary sources checked
- https://openai.com/index/chain-of-thought-monitoring/ and https://arxiv.org/abs/2503.11926 — direct optimization against reasoning monitors can reduce visibility of continuing reward hacking in studied settings.
- https://openai.com/index/evaluating-chain-of-thought-monitorability/ — monitorability depends on the property, channel, task, and evaluation; ordinary training need not universally degrade it.
- https://alignment.openai.com/accidental-cot-grading/ — accidental grading of reasoning is a relevant training-pathway confound.
- https://openai.com/index/reasoning-models-chain-of-thought-controllability/ — controllability and adversarial monitor evasion are related but distinct measurements.

## Proposed protocol
Measure independent sandbox behavior labels, hacking opportunities, task success, explicit verbalization, and frozen-monitor recall at matched false-positive rate. Include no-extra-pressure and untouched controls; action-only and combined monitors help locate signal loss. Test entropy bonuses, reasoning-token divergence penalties, a precisely specified on-policy distillation recipe, and length penalties as reference. Use fixed base/task/reward/access/rollout settings where possible, multiple seeds, checkpoints, and held-out tasks. Compare both unconditional outcomes and carefully marked length/task/hack-type strata; matching a post-treatment variable is descriptive and can introduce selection bias.

## Scientific limits
Generated reasoning is an evidence channel rather than a complete internal transcript. Reduced explicit wording need not imply loss of all detectable signal, nor prove intentional concealment. Frozen monitor failure may be monitor distribution shift; a refreshed monitor is a separate secondary repair result. Ordinary entropy/distillation effects are proposed questions, not established results. No setting effect at8B should stop the expensive32B follow-up, with effect-size uncertainty documented.

## Supplied planning claims
$35k–$55k compute, not a quote/funding guarantee. Four-month roadmap and parameter scales contingent on pilot success, accessible weights/rollouts, sufficient annotation and replication reserve. Recheck literature novelty before pitching.

## On-policy distillation clarification
Primary mechanism source: https://thinkingmachines.ai/blog/on-policy-distillation/ and https://tinker-docs.thinkingmachines.ai/cookbook/recipes/distillation/ — student-generated trajectories receive fixed-teacher per-token feedback. The repaired page2 specifies this particular recipe rather than treating arbitrary selection of own outputs as equivalent. Fix teacher identity, feedback weight, and reasoning-token coverage; distinguish teacher-target distillation from frozen-reference regularization. Do not assume a specific retired checkpoint is currently supported.
