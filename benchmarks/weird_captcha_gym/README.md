# Weird CAPTCHA Gym

A Gym-Anything benchmark for weird CAPTCHA-inspired visual puzzles for computer-use agents.

This package mirrors the CUA-World benchmark shape:

```text
benchmarks/weird_captcha_gym/
  environments/<mechanic_env>/env.json
  environments/<mechanic_env>/tasks/<task_id>/task.json
  splits/*.json
  registry/
```

Each environment is a puzzle-family environment. The action interface is common across all environments: screenshots plus mouse/keyboard actions. Individual tasks define puzzle setup, instructions, hidden generation metadata, and outcome verifiers; they do not define custom action subsets.

Current status: 65 environment folders, comprising 63 built/prototype designs and 2 rejected infrastructure pilots. There are no remaining concept cards or scaffold folders. Forty-three mechanics that previously existed only as Incubator or Pack III–VI selections now have real environments, seeded generators, ordinary browser interaction paths, server graders, exported verifiers, and local screenshot evidence. This is still a candidate corpus, not a benchmark-ready release.

- `reverse_identity_gate_env` and `moving_checkbox_evasive_button_env` are the two rejected pilots. They remain as infrastructure history and are excluded from the built corpus.
- The foundational visual, source-grounded, and first two interaction collections retain their original evidence directories (`apple_grid_v1`, `cursor_lens_v1`, `modifier_stack_v1`, `board_game_v1`, `source_mechanics_v1`, `interaction_first_five_v1`, and `interaction_second_five_v1`).
- Incubator batches one through five are now built. Batches one and two contain ten interaction-heavy designs; the historical batches three through five contribute thirteen more. Their browser/server/verifier summaries live under `evidence/incubator_batch_one_v1/` through `evidence/incubator_batch_five_v1/`.
- Interaction III and IV are five-mechanic built packs with evidence under `evidence/incubator_batch_six_v1/` and `evidence/incubator_batch_seven_v1/`.
- Interaction V is a five-mechanic built pack—photograph geometry, recorded ghosts, recursive scale, projection topology, and forced perspective—with evidence under `evidence/incubator_batch_eight_v1/`.
- Interaction VI is a five-mechanic built pack—LIDAR, tomography, three-camera teleoperation, deformable cable physics, and portal coordinate transforms—with evidence under `evidence/incubator_batch_nine_v1/`.

All 63 built designs have local scripted browser, server-grade, and exported-verifier evidence. That does not imply human usability, benchmark validity, or model difficulty. Six mechanics preserve direct human feedback from this execution history; VNC human calibration is still pending for the other 57 designs, and no viewer-specific human-evidence claim is made. Automated AVF screenshots are evidence, not human feedback.

For mechanics that render spatial or physical worlds, the browser receives the geometry it must draw, hit-test, and collide with. It does not receive private solver routes or answer plans. The server independently replays submitted primitive actions against its own copy of the geometry, timing, collision, line-of-sight, and completion rules. Public render geometry is therefore an explicit screenshot/action-agent boundary, not a secrecy guarantee against an agent that can inspect page state or network responses.

Use `all` only as a development surface. The `verified` split remains intentionally empty until tasks pass the quality gate in `docs/benchmark-quality-gate-v0.md`, including real-runner, human, and agent evidence.

The complete interaction-first design history, human VNC findings, implementation corrections, validation status, and future-maintainer checklist are recorded in [`docs/interaction-puzzle-field-notes.md`](docs/interaction-puzzle-field-notes.md).

## Visual Dashboard

The benchmark includes a screenshot-first environment hub for browsing all 65 folders: 63 evidence-backed built designs and 2 rejected archive records. All twenty Pack III–VI selections and all historical Incubator selections have been promoted to real, launchable environment records; the dashboard contains zero concept or scaffold cards. It can inspect evidence, open every built task as an ordinary local browser app, preserve the isolated VNC path, store human reviews, and prepare or run evaluations through the existing CLI contract. A Survey-free static export can be shared with collaborators; its authenticated loopback companion keeps all execution and administrative controls on each collaborator's own computer.

[Open the hosted CAPTCHA Bench dashboard](https://cmu-l3.github.io/gym-anything/captcha-bench/).

```bash
PYTHONPATH=src python benchmarks/weird_captcha_gym/dashboard/server.py --open --runner avf
```

The dashboard is available at <http://127.0.0.1:8767> and binds to localhost by default. See [`dashboard/README.md`](dashboard/README.md) for product surfaces, architecture, and verification commands; see [`dashboard/RESEARCH.md`](dashboard/RESEARCH.md) for the Prime Intellect and adjacent benchmark research that informed it.

Run the quality audit with:

```bash
python benchmarks/weird_captcha_gym/tools/audit_quality.py --strict
```

## Developer Answer Reveal

The normal benchmark URL must not expose answers. For manual inspection only, start the server with `WEIRD_CAPTCHA_CHEAT_PASSWORD=<password>` or write the password to `$WEIRD_CAPTCHA_STATE_DIR/cheat_password.txt`, then open `/?cheat=1`. Submitting the password reveals the current generated answer for the active mechanic.
