# Interpretability cards: source and content notes

All cards use original beginner-friendly explanations. Analogies are followed by mechanisms and limitations. The notes below identify primary references used to verify terminology; diagrams are schematic examples, not claims about a named production model.

1. Mechanistic interpretability: mechanisms require intervention tests; maps are partial. [Transformer circuits framework](https://transformer-circuits.pub/2021/framework/index.html).
2. Residual stream: token vectors carry additive updates from attention and MLP blocks; normalization matters. [Framework](https://transformer-circuits.pub/2021/framework/index.html).
3. Attention head: query-key attention weights mix values, then an output projection writes an update. Attention weights alone do not establish a full causal explanation. [Framework](https://transformer-circuits.pub/2021/framework/index.html).
4. MLP layer: positionwise nonlinear transformations, with possible gating. Avoids treating one neuron as one concept. [Framework](https://transformer-circuits.pub/2021/framework/index.html).
5. Feature: method-dependent meaningful activation patterns; labels approximate meaning. [Towards Monosemanticity](https://transformer-circuits.pub/2023/monosemantic-features/index.html).
6. Linear representation hypothesis: useful hypothesis about directions or subspaces, not a universal law. [Original paper](https://arxiv.org/abs/2311.03658).
7. Polysemanticity: multiple unrelated activation contexts for a neuron. [Toy Models of Superposition](https://transformer-circuits.pub/2022/toy_model/index.html).
8. Superposition: more features than dimensions, with interference; evidence and geometry vary. [Toy Models of Superposition](https://transformer-circuits.pub/2022/toy_model/index.html).
9. Monosemanticity: comparatively coherent feature meaning; not perfect one-to-one semantic switches. [Towards Monosemanticity](https://transformer-circuits.pub/2023/monosemantic-features/index.html).
10. SAE: sparse encoding and reconstruction, with errors and missed or split features. [Towards Monosemanticity](https://transformer-circuits.pub/2023/monosemantic-features/index.html).
11. Transcoder / crosscoder: predicts a component transformation versus shared representation across layers/models. [Crosscoders](https://transformer-circuits.pub/2024/crosscoders/index.html), [Circuit tracing](https://transformer-circuits.pub/2025/attribution-graphs/methods.html).
12. Circuit: interacting components contributing to behavior, tested with interventions. [Framework](https://transformer-circuits.pub/2021/framework/index.html).
13. Induction head: classic repeated-context copying, not all in-context learning. [Induction heads](https://transformer-circuits.pub/2022/in-context-learning-and-induction-heads/index.html).
14. Attribution graphs / circuit tracing: partial graphs based on interpretable approximations, with omitted computation and model error. [Methods paper](https://transformer-circuits.pub/2025/attribution-graphs/methods.html).
15. Linear probe: decodability is distinct from causal use; held-out evaluation required. [Linear representation hypothesis](https://arxiv.org/abs/2311.03658).
16. Logit lens / tuned lens: final readout versus learned affine intermediate translators; does not show literal reasoning. [Tuned Lens](https://arxiv.org/abs/2303.08112).
17. Activation patching: clean/corrupt interchange interventions depend on examples and metrics. [Circuit tracing validation](https://transformer-circuits.pub/2025/attribution-graphs/methods.html).
18. Ablation: removal/replacement interventions can be distorted by backup paths and unnatural states. [Framework](https://transformer-circuits.pub/2021/framework/index.html).
19. Steering: changes activations during inference, without guaranteeing target behavior. [CAA](https://arxiv.org/abs/2312.06681).
20. Steering vector / CAA: mean contrast direction scaled and added to activations; examples and scale matter. [CAA](https://arxiv.org/abs/2312.06681).
21. Feature clamping: controlling a feature activation is an imperfect conceptual intervention. [Scaling Monosemanticity](https://transformer-circuits.pub/2024/scaling-monosemanticity/index.html).
22. RepE: high-level population representations for reading/control; concept labels need validation. [Original paper](https://arxiv.org/abs/2310.01405).
23. Refusal direction: observed strong directions in studied models, not a universal single safety switch. [Original refusal-direction paper](https://arxiv.org/abs/2406.11717), [2026 qualification](https://arxiv.org/abs/2602.02132).
24. Persona vectors: measured behavioral trait directions, not evidence of human personality or consciousness. [Anthropic](https://www.anthropic.com/research/persona-vectors).
25. Model diffing: shared/changed feature comparison, with matching and causality caveats. [Crosscoders](https://transformer-circuits.pub/2024/crosscoders/index.html).
26. Introspection: controlled evidence of limited internal-state access, unreliable reports, no inference of consciousness. [Anthropic introspection research](https://www.anthropic.com/research/introspection), [2026 adapters](https://alignment.anthropic.com/2026/introspection-adapters/).
27. White-box vs. black-box: internals versus observable behavior; neither guarantees safety. [Framework for white-box mechanisms](https://transformer-circuits.pub/2021/framework/index.html).

Generation: built-in image_gen, one separate call per card. Exact prompts are in ../prompts/04-*.txt. Images are in ../04-interpretability/. Every final image was visually inspected for readable text, coherent layout, and material factual mistakes. Cards 06, 08, 10, 11, 12, 14, 16, 22, 25, and 27 use six panels; remaining topics use four. Cards 02 and 03 were regenerated to remove diagram-production wording from body text. Card 03 also received a targeted information-flow arrow-label correction. PNG signatures and 1024 × 1536 dimensions were checked for all 27 files; see the companion manifest.

Acronym QA, October 12, 2026: all 27 cards inspected with visual reading plus OCR. Four targeted edits added clear header glossary lines: MLP = MULTILAYER PERCEPTRON on residual stream, attribution graphs/circuit tracing, and ablation; SAE = SPARSE AUTOENCODER on feature clamping. Existing MLP, SAE, CAA, RepE, and Q/K/V expansions confirmed on other relevant cards. All four edited images visually inspected and accepted. Category README includes common AI expansion and glossary.
