# Dashboard Product Research

Research performed 2026-07-10 before implementation.

## Products inspected

### Prime Intellect Environments Hub

- [Environment Hub](https://app.primeintellect.ai/dashboard/environments)
- [Evaluation dashboard](https://app.primeintellect.ai/dashboard/evaluations)
- [Environment Hub documentation](https://docs.primeintellect.ai/tutorials-environments/environments)
- [Environment announcement and lifecycle](https://www.primeintellect.ai/blog/environments)
- [Verifiers overview](https://docs.primeintellect.ai/verifiers/overview)

The strongest product idea is not a particular card treatment. It is that one environment identity moves through a coherent lifecycle: discovery, inspection, execution, evaluation, and eventually training. That makes an environment hub a control plane rather than a static gallery.

Prime's public hub is optimized for a large text-heavy catalog. CAPTCHA Bench needs the same lifecycle but a different information hierarchy: the artifact is inherently visual, and its difficulty often cannot be inferred from metadata alone. Screenshot evidence therefore became the dominant unit in the Observatory, catalog, and dossier views.

### Adjacent evaluation systems

- [Terminal-Bench leaderboard](https://www.tbench.ai/leaderboard) — useful precedent for explicit benchmark versions and treating evaluation results as a product surface.
- [OSWorld](https://osworld-v1.xlang.ai/) — useful precedent for evaluating agents in real interactive computer environments instead of reducing tasks to static perception questions.

These reinforced two choices: preserve the benchmark's actual runtime path, and keep future evaluation history adjacent to environment discovery rather than building an unrelated runner UI.

## Decisions carried into the implementation

1. **A screenshot is evidence, not the task.** The visual system repeatedly states the benchmark's interaction-first thesis while still making screenshots useful for discovery.
2. **One catalog object powers every surface.** Environment folders, task metadata, screenshots, verifier evidence, VNC launch, and evaluation commands are joined by the same environment ID.
3. **Built and rejected work remain visibly different.** The final catalog contains 65 real folders: 63 built designs and 2 rejected pilots, with zero concept or scaffold cards. Forty-three formerly queued or selected Incubator/Pack III–VI mechanics became built only after real folders, verifiers, browser evidence, and launch contracts existed.
4. **Launching means launching the real environment.** One-click VNC calls Gym-Anything, waits for its published session information, and exposes teardown/logging; there is no simulated success state.
5. **Evaluation is safe by default.** The evaluation form creates an argument-validated command preview unless the operator explicitly disables preview mode.
6. **The visual language should feel like a field station.** The design uses an editorial/scientific observatory metaphor, evidence filmstrips, specimen numbering, and restrained acid color rather than generic SaaS analytics cards.
7. **No frontend build step.** A benchmark-local dashboard should be immediately operable in a repository checkout, including while environment infrastructure is being debugged.
8. **Research selection stays upstream and out of the shared product.** The source survey remains repository research material; the collaborator dashboard ships only implemented environment records and never publishes the multi-gigabyte corpus.
9. **Shared presentation, local execution.** A static dashboard can be public while its authenticated loopback companion launches the real browser task, VNC guest, review write, or evaluation process on each collaborator's own computer.
9. **Provenance must survive curation.** Every selectable record links back to source dossiers, local artifact paths, extraction notes, original URLs, and artifact-use policy. Related benchmark environments are joined only through explicit `source_anchors`, never title similarity.
10. **Large corpora require progressive disclosure.** Atlas cards carry representative evidence, concrete instances are server-paginated, item dossiers resolve only the relevant files, and source dossiers paginate the complete archive. This keeps the 3.6 GB benchmark corpora inspectable without sending thousands of records to the browser at once.
11. **Counts must describe their unit.** Designs, source implementations, challenge records, and raw visual assets are different things. A nine-cell option grid is one challenge with nine assets—not nine CAPTCHAs—and an advertised source count is not expanded unless individual records are locally enumerated.
12. **Render geometry is an interaction contract, not a secret.** A spatial browser must receive enough geometry to draw, hit-test, and collide honestly. Hidden routes and answers stay server-side; the grader independently replays primitive actions against its own geometry. This is a screenshot/action boundary, not protection against page-state or network inspection.
13. **Script verification is not human evidence.** All 63 built designs have local browser/server/exported-verifier evidence, while direct VNC calibration remains incomplete for many and the `verified` split stays empty. No specific VNC viewer is treated as proof of usability.

## Shipped research layer

The environment hub now indexes 63 evidence-backed builds and 2 rejected archive pilots. Interaction V and VI are represented by the complete batch-eight and batch-nine evidence summaries rather than roadmap placeholders. The shared dashboard deliberately omits the upstream survey and instead preserves the complete implemented catalog, evidence-rich dossiers, solution films, persistent human reviews, direct localhost browser play, isolated VNC sessions, and evaluation controls.

## Intended next layer

The current backend already has a real evaluation-process lifecycle. A later iteration can parse result artifacts into per-environment success rates, trajectory links, model comparisons, and replayable failure slices without changing the environment identity model or launch surface. Promotion into the currently empty `verified` split still requires the documented real-runner, human, and agent quality gate.
