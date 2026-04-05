# Gym-Anything

Gym-Anything is a runtime and benchmark repository for turning existing software into Gym-like environments for computer-use agents.

It has four distinct layers:

- `src/gym_anything/`: the core runtime library
- `src/gym_anything/remote/`: distributed execution infrastructure
- `src/gym_anything/dashboards/`: packaged dashboard apps for runtime and run inspection
- `benchmarks/cua_world/`: the primary benchmark suite, including corpus payload and support files
- `agents/`: reference agents and evaluation harnesses

Tutorial examples live under `examples/tutorials/`. Archived or superseded CUA-World benchmark variants live under `benchmarks/cua_world/historical/`.
The project website source lives under `website/`, while the active Mintlify docs project lives under `docs/`. The previous MkDocs docs and generated site are archived under `legacy/mkdocs/`.

This distinction matters. The core runtime is the stable product surface. The benchmark corpus is large and heterogeneous. The agent harnesses are useful reference tooling, but they are not the primary product surface.

## Current Repository State

In this checkout, the benchmark corpus contains:

- `195` environment specs (`env.json` or `env.yaml`)
- `7,662` task specs (`task.json`, `task.yaml`, or `task.yml`)

The corpus changes over time. Treat those numbers as a snapshot of the current repository, not a permanent contract.

## What Is Implemented Today

- Environment construction via `make()` and `from_config()`
- Core environment lifecycle via `GymAnythingEnv.reset()`, `step()`, and `close()`
- Runner backends for Docker, QEMU-in-Apptainer, Android AVD-in-Apptainer, direct Apptainer, and local smoke tests
- Checkpoint caching for Docker, QEMU, and AVD runners
- Optional QEMU `savevm`/`loadvm` fast restore
- Programmatic verifiers and SSIM image matching
- Host-side verifier helpers for file transfer, command capture, and VLM queries
- Step-by-step screenshot trajectories on all working runners
- Remote execution through master/worker/dashboard services and `RemoteGymEnv`
- Packaged dashboards for cluster monitoring and offline trajectory inspection
- First-class verification commands for spec, corpus, and task-pipeline checks

## Important Caveats

- The spec dataclasses are smaller than the benchmark JSON files. Extra keys in `env.json` and `task.json` are usually tolerated but ignored by the core loader unless code reads them separately.
- `TaskSpec` now preserves common top-level task metadata such as `description`, `version`, `name`, and `tags`, but benchmark-specific extra keys are still passthrough metadata rather than first-class runtime behavior.
- Supported verifier modes are currently `program`, `image_match`, and `multi`.
- Runner differences such as recording, checkpointing, `use_savevm`, and `user_accounts` are part of the supported compatibility contract. See [docs/core/runners.mdx](docs/core/runners.mdx).
- `python -m agents.evaluation.run_single` and `run_batch` are reference harnesses. They still include optional runner-specific setup behavior.
- `pip install -e .` now installs the Python runtime dependencies for the shipped package surface. System dependencies such as Docker, Apptainer, QEMU, and host `ffmpeg` are still external prerequisites, but `gym-anything doctor` now checks them explicitly.
- As of March 8, 2026, `gym-anything verify corpus benchmarks/cua_world/environments` reports `7,277` verified tasks and `385` failed tasks. The current failures are all missing hook asset references (`763` `missing_hook_reference` issues).
- `benchmarks/cua_world/splits/verified.json` is the verifier-backed supported task surface for release-facing evaluation. The raw corpus remains available.

## Quick Start

### Install

```bash
git clone <repo-url>
cd <repo-dir>
pip install -e .
```

Check system prerequisites before your first real run:

```bash
PYTHONPATH=src python -m gym_anything.cli doctor
```

Optional extras:

```bash
pip install -e ".[services]"
pip install -e ".[agents]"
pip install -e ".[vlm]"
```

If you use hosted model APIs or guest-side DockerHub pulls, copy `.env.example` to `.env` and fill in the keys you need.

System dependencies depend on the runner you use:

- Docker workflows need a working Docker daemon.
- QEMU workflows need Apptainer and usually `/dev/kvm`.
- Android AVD workflows need Apptainer plus emulator support.

See [Quickstart](docs/quickstart.mdx) for the new docs starting point.

### Load and Run a Task

```python
from gym_anything import from_config

env = from_config(
    "benchmarks/cua_world/environments/zotero_env",
    task_id="create_saved_search",
)

obs = env.reset(seed=42, use_cache=False)

obs, reward, done, info = env.step([
    {"mouse": {"left_click": [300, 200]}},
    {"keyboard": {"text": "Papers Since 2010"}},
])

# When the agent believes the task is complete, explicitly finalize:
obs, reward, done, info = env.step([], mark_done=True)

print(reward, info.get("verifier"))
env.close()
```

### Run a Reference Agent

```bash
python -m agents.evaluation.run_single \
  --env_dir benchmarks/cua_world/environments/zotero_env \
  --task create_saved_search \
  --agent ClaudeAgent \
  --agent_args '{"model":"claude-opus-4","exp_name":"demo"}'
```

## Where To Read Next

- [docs/introduction.mdx](docs/introduction.mdx): framework overview
- [docs/quickstart.mdx](docs/quickstart.mdx): installation and first run
- [docs/core/overview.mdx](docs/core/overview.mdx): core runtime surface
- [docs/core/environments.mdx](docs/core/environments.mdx): environment contract
- [docs/core/runners.mdx](docs/core/runners.mdx): runtime backends
- [docs/core/remote.mdx](docs/core/remote.mdx): remote execution model
- [docs/benchmarks/overview.mdx](docs/benchmarks/overview.mdx): benchmark layer
- [docs/agents/overview.mdx](docs/agents/overview.mdx): reference agent layer
- [legacy/mkdocs/README.md](legacy/mkdocs/README.md): archived MkDocs-era docs

## Repository Layout

```text
.
├── src/gym_anything/          core runtime library
├── benchmarks/cua_world/environments/   benchmark environments and tasks
├── benchmarks/cua_world/splits/         train/test split definitions and verified surface
├── benchmarks/cua_world/registry/       split loaders and registry helpers
├── benchmarks/cua_world/reports/        generated verification manifests
├── benchmarks/cua_world/historical/     archived benchmark variants
├── examples/tutorials/        lightweight tutorial environments
├── agents/agents/             reference agent implementations
├── agents/evaluation/         single-run and batch harnesses
├── agents/shared/             shared model/prompt utilities
├── src/gym_anything/dashboards/ packaged UI applications
├── src/gym_anything/remote/   remote client, master, worker, dashboard, monitoring
├── docs/                      Mintlify docs project
├── legacy/mkdocs/             archived MkDocs docs and generated site
└── website/                   project website assets
```

The new docs surface is being rebuilt from scratch in `docs/`.
