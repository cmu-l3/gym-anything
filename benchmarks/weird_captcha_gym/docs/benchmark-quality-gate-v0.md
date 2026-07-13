# Benchmark Quality Gate v0

Date: 2026-07-08

This benchmark is not ready just because an environment boots, renders, submits, and verifies. A task is benchmark-ready only if it behaves like a CAPTCHA-style visual puzzle rather than a tutorial, demo, or toy app.

## Hard Requirements

- The visible UI may show a terse CAPTCHA-style prompt, selection state, `PASS`, and `FAIL`.
- The visible UI must not show partial correctness, answer counts, missed items, extra items, scoring explanations, debug text, or next-step hints.
- The visible UI must not explain the mechanism beyond the prompt. No rules panels, training copy, "how to solve" text, or "end the episode" text.
- Failure may load a new instance in the same mechanic, but it must not reveal why the attempt failed.
- The task must have a real outcome verifier. Placeholder verifiers are never benchmark-ready.
- The normal computer-use surface must not expose answer labels, target IDs that encode semantics, target masks, or anything a screen-only agent should not infer from pixels. Browser render state may contain procedural geometry when the client needs it to draw the canvas, but it must not be visible in the page UI or reachable through allowed mouse/keyboard-only actions.
- Asset provenance must be recorded. Assets can be collected, generated, or procedural, but the manifest must say which.
- Template-only procedural art is not enough unless the generator has enough combinatorial variation to make repeated runs non-trivial.
- A task needs screenshot evidence from the real runner before it can be promoted.
- Developer answer reveal must be disabled by default and hidden from the normal task URL. If enabled for manual inspection, it must require an out-of-band password and a separate `?cheat=1` URL.

## Frozen historical v0 classification (superseded)

The bullets below record the 2026-07-08 snapshot and are not the current catalog. The live tree now contains 65 folders—63 built/prototype designs, 0 scaffolds, and 2 rejected pilots—while the `verified` split remains empty pending this gate.

- `reverse_identity_gate`: rejected infrastructure pilot. It proves runtime plumbing, not benchmark quality.
- `moving_checkbox_evasive_button`: rejected infrastructure pilot. It reads like a tutorial/demo.
- `surreal_apple_on_tree_grid`: visual candidate. It has one dynamic task with fresh random generation on page load/refresh, local screenshot evidence, AVF screenshots, retry-on-fail behavior, a provenance manifest, a dev-only answer reveal, and a real outcome verifier.
- `cursor_lens_reveal`: visual candidate. It has one dynamic task with a mouse-driven reveal lens, fresh random generation on page load/refresh, local screenshot evidence, AVF screenshots, retry-on-fail behavior, a provenance manifest, a dev-only target-coordinate reveal, and a real outcome verifier.
- `modifier_stack_image_grid`: visual candidate. It has one dynamic 4x4 grid with procedural object silhouettes, stacked visual corruptions, fresh random generation on page load/refresh, local and AVF screenshot evidence, retry-on-fail behavior, a provenance manifest, a dev-only answer reveal, and a real outcome verifier.
- `semantic_drag_drop_absurdity`, `reload_interruption`, `rotate_wrong_thing_upright`, `bureaucratic_signature_trap`, `wonky_text_hostile_rendering`, and `temporal_memory_first_change`: source-grounded non-grid visual candidates. They have fresh procedural generation, local Playwright screenshot evidence, AVF reset screenshots, a provenance manifest, password-gated dev reveal support, and real outcome verifiers. They still need solved AVF trajectory evidence before promotion.
- At this historical snapshot, the remaining mechanics were scaffolds with placeholder verifiers.

## Promotion Checklist

Before a task can move to `metadata.status = "benchmark_ready"` and the registry `verified` surface, it needs:

- at least one AVF screenshot showing the first screen;
- at least one failed attempt screenshot showing only `FAIL` plus a fresh instance;
- at least one passing run with verifier score 100;
- an asset/provenance manifest;
- a per-task audit pass from `benchmarks/weird_captcha_gym/tools/audit_quality.py --task <task_id> --strict`;
- no visible tutorial/hint/debug strings in the runtime surface.
