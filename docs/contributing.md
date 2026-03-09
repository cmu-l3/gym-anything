# Contributing

## Contribution Principle

This repo is only maintainable if code, benchmark content, and docs stay aligned.

If you change runtime behavior:

- update the implementation
- update the docs
- state runner coverage and limitations explicitly

## Where Changes Go

- reusable runtime code -> `src/gym_anything/`
- benchmark environments and tasks -> `benchmarks/environments/`
- reference agents and evaluation harnesses -> `baselines/`
- remote services -> `services/`
- offline utilities -> `tools/`
- experiments and one-offs -> `research/`

## Adding A New Environment

1. Create `benchmarks/environments/<env_name>/`.
2. Add `env.json`.
3. Add shared scripts under `scripts/`.
4. Add one or more tasks under `tasks/<task_id>/`.
5. Add verifier logic for each task.
6. Register split information in `benchmarks/splits/<env_name>_split.json`.
7. Document runner requirements and any known caveats.

Use [Environment Authoring](environment-authoring.md) as the canonical guide.

## Adding A New Task

1. Add `task.json`.
2. Add `setup_task.*` only if the task really needs per-task preparation.
3. Add `export_result.*` if the verifier needs structured output.
4. Prefer programmatic verification.
5. Put verifier constants into `task.json -> metadata`.

## Adding A New Runner Feature

If you introduce a new spec field or extend a runner:

1. add the field to the dataclass if it should be runtime-recognized
2. wire it through the consuming runner or env logic
3. document which runners honor it
4. do not imply cross-runner support unless it exists

## Docs Expectations

Do not write aspirational docs as if a feature already exists.

If something is:

- partial
- runner-specific
- experimental
- only used by research harnesses

say so directly.

## Verification Before Sending A Change

At minimum, run the narrowest relevant checks you can:

- import smoke tests
- CLI `--help`
- `verify spec` on affected envs/tasks
- a real reset/step/finalize flow when changing runtime behavior

For benchmark contributions, verify that `step([], mark_done=True)` produces a sensible verifier result path.
