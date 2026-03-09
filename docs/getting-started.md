# Getting Started

## Scope

This page covers the minimum practical setup for running the current codebase.

It intentionally separates:

- core runtime usage
- benchmark loading
- research harness usage

## Prerequisites

### Python

- Python `3.10+`

### System Runtime

Choose the runner path you intend to use:

- Docker path: Docker daemon available locally
- QEMU path: Apptainer available, usually plus `/dev/kvm`
- Android AVD path: Apptainer plus emulator support
- Local smoke path: no container runtime, but functionality is minimal

### Python Dependencies

`pip install -e .` now installs the shipped Python runtime dependencies.

Optional extras:

- `pip install -e ".[services]"` for master/worker/dashboard services
- `pip install -e ".[baselines]"` for reference agents and evaluation harnesses
- `pip install -e ".[vlm]"` for hosted VLM backends

System dependencies such as Docker, Apptainer, QEMU, Android emulator support, and host `ffmpeg` are still external.

Check them before your first real run:

```bash
PYTHONPATH=src python -m gym_anything.cli doctor
PYTHONPATH=src python -m gym_anything.cli doctor --runner docker
```

## Install

```bash
git clone <repo-url>
cd <repo-dir>
python -m venv .venv
source .venv/bin/activate
pip install -e .
```

If you want to use the package without installing it, run commands with `PYTHONPATH=src`.

## First Environment Run

### Python API

```python
from gym_anything import from_config

env = from_config(
    "benchmarks/environments/zotero_env",
    task_id="create_saved_search",
)

obs = env.reset(seed=42, use_cache=False)

print(obs["screen"]["path"])

obs, reward, done, info = env.step([
    {"mouse": {"left_click": [200, 120]}},
    {"keyboard": {"text": "Papers Since 2010"}},
])

obs, reward, done, info = env.step([], mark_done=True)
print(reward, info.get("verifier"))

env.close()
```

### Important Runtime Semantics

- `step()` expects a list of low-level action dicts.
- `mark_done=True` is what triggers `post_task` and final verification.
- `close()` also runs `post_task` and final verification if the episode has not already been finalized.
- `mark_done=True` is still the best path when you want the verifier result back immediately in the `step()` return value.
- Each `reset()` creates a new episode directory under `recording.output_dir`, even if continuous recording is disabled.

## Using Caching

```python
obs = env.reset(
    seed=42,
    use_cache=True,
    cache_level="post_start",
)
```

Current caching support:

- Docker: yes
- QEMU: yes
- Android AVD: yes
- Direct Apptainer: placeholder methods only
- Local: no

`use_savevm=True` is only meaningful for the QEMU runner.

## Smoke CLI

The built-in CLI is small and useful for validation and smoke tests:

```bash
PYTHONPATH=src python -m gym_anything.cli verify spec benchmarks/environments/zotero_env --task create_saved_search
PYTHONPATH=src python -m gym_anything.cli doctor --runner docker
PYTHONPATH=src python -m gym_anything.cli run benchmarks/environments/zotero_env --task create_saved_search --steps 3
```

The `run` subcommand is not a full agent runner. It performs a simple episode loop with empty actions.

## Reference Evaluation Harness

The research harnesses live in `baselines/evaluation/`:

```bash
python -m baselines.evaluation.run_single \
  --env_dir benchmarks/environments/zotero_env \
  --task create_saved_search \
  --agent ClaudeAgent \
  --agent_args '{"model":"claude-opus-4","exp_name":"demo"}'
```

Treat these scripts as reference experiments, not as a stable public interface. They still include optional environment-specific setup behavior.

## Next Steps

- [API](api.md)
- [Specs](specs.md)
- [Runners](runners.md)
- [Tasks & Verifiers](tasks-verifiers.md)
- [Environment Authoring](environment-authoring.md)
