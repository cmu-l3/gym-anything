# Repository Structure

This repository is intentionally split by responsibility.

## Canonical Directories

- `src/gym_anything/`
  The product library. New reusable runtime code belongs here.

- `benchmarks/cua_world/environments/`
  Environment and task corpus. This is benchmark content, not library code.

- `benchmarks/cua_world/historical/`
  Archived benchmark variants, superseded environments, and historical corpus material that should not stay in the canonical benchmark set.

- `benchmarks/cua_world/splits/`
  Split JSON files.

- `benchmarks/registry/`
  Python loaders and split helpers.

- `examples/tutorials/`
  Lightweight tutorial or demo environments that are useful for onboarding, but are not part of the benchmark corpus.

- `baselines/agents/`
  Reference agents.

- `baselines/common/`
  Shared baseline utilities.

- `baselines/evaluation/`
  Research evaluation harnesses.

- `services/`
  Master, worker, and dashboard services.

- `tools/`
  Offline utilities and maintenance helpers.

- `scripts/maintenance/`
  Repo-level audit and cleanup scripts.

- `docs/`
  Reference documentation.

- `research/`
  Experimental and archived code that is not part of the supported product surface.

- `third_party/`
  Vendored binaries or external artifacts that cannot yet be externalized.

## Benchmark Placement Rules

Inside `benchmarks/cua_world/environments/<env_name>/`:

- keep runtime files at the env root, in `scripts/`, and under `tasks/`
- keep large staged datasets in `data/` and app/plugin bundles in `addons/` when needed
- keep environment-local documentation and snippets in `docs/`
- keep environment-local dev harnesses and one-off validation scripts in `dev/`
- keep audit and status docs in `metadata/`
- keep screenshots and validation evidence in `evidence/`
- keep environment-local raw run outputs in `artifacts/` when they are intentionally retained with the environment

Allowed env-level directories:

- `scripts/`
- `tasks/`
- `assets/`
- `config/`
- `utils/`
- `data/`
- `addons/`
- `docs/`
- `dev/`
- `metadata/`
- `evidence/`
- `artifacts/`

## Product Versus Research

When deciding where code belongs:

- if it is reusable runtime logic, put it in `src/gym_anything/`
- if it is a reference experiment, put it in `baselines/` or `research/`
- if it is a deployable HTTP service, put it in `services/`
- if it is offline maintenance or analysis, put it in `tools/`

## Documentation Rule

Docs should describe the canonical locations above, not old root-level wrappers or aliases.
