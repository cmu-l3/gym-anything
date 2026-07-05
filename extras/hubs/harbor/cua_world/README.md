## CUA-World-Long → Harbor Adapter

**Notice:**
1. This adapter follows the Harbor adapter template. The source of truth for the adapter code lives in the [gym-anything repository](https://github.com/cmu-l3/gym-anything) under `extras/hubs/harbor/cua_world/` and is mirrored here.
2. The default task preparation dir is `datasets/cua-world`.
3. Tutorial references: [agent version](https://www.harborframework.com/docs/datasets/adapters), [human version](https://www.harborframework.com/docs/datasets/adapters-human).

## Overview

CUA-World-Long evaluates long-horizon computer use in real professional software. Each task boots a real desktop VM (Ubuntu guests with the target application installed and open), the agent operates the GUI through screenshots and mouse/keyboard actions, and the episode is graded against each task's checklist by a VLM judge by default (gemini-3.5-flash), with the task's own programmatic verifier available via config.

- Task types: professional GUI workflows (image editing, CAD, EHR systems, office suites, scientific tools, and more), one task per software.
- Dataset size: 201 tasks, one per software environment, enumerated programmatically from the benchmark's `long_horizon` split (the paper describes the split as 200 tasks; the registry carries 201 entries and the adapter uses the registry as ground truth).
- Provenance: the flagship split of Gym-Anything's CUA-World benchmark (Aggarwal, Neubig, Welleck; Carnegie Mellon University). Tasks were designed through trajectory-guided analysis of agent failure modes and are all manually verified.
- Main adaptation choices: tasks run inside a QEMU-in-container runtime (KVM required, same pattern as the OSWorld adapter); grading runs in the container, outside the agent-controlled VM, through the benchmark's real verifier pipeline; no scripted oracle solutions ship (see Notes & Caveats).

## What is CUA-World-Long?

CUA-World-Long is the headline evaluation of [Gym-Anything](https://github.com/cmu-l3/gym-anything), a library that turns real software into computer-use agent environments. The split contains one particularly challenging task per software, designed by analyzing where strong agents fail on easier tasks and constructing harder ones that exploit those weaknesses. Tasks often require 200+ steps for humans and 500+ steps for models; the best model at publication passed 14.0%. Scoring is the task verifier's verdict: sparse tasks give 0/1, partial-credit tasks give score/100, surfaced in Harbor as `reward` plus `passed` and `score` named metrics. The default grading mode here is the VLM checklist (matching the benchmark's hosted deployment: some programmatic verifiers read live, agent-mutable application state, so a VLM judges the trajectory against each task's manually written checklist instead); the programmatic mode remains available via config.

## Adapter Features

- Programmatic task generation from the gym-anything registry (task IDs, instructions, and tags are read from each task's `task.json`; task IDs are preserved as `{env_name}__{task_id}`).
- Self-contained task images: a generic Dockerfile installs gym-anything at a pinned ref and boots the task's guest VM via QEMU inside the container (the same runtime shape the OSWorld adapter uses).
- Shared image-cache volume (`harbor-gym-anything-cache`): the guest image is provisioned once per host and reused across trials via copy-on-write overlays.
- In-container grading through the benchmark's real verifier pipeline, isolated from the agent-controlled VM. Default mode is the VLM checklist (gemini-3.5-flash judging each task's `vlm_checklist.json`; requires `GEMINI_API_KEY`); set `verifier.mode` to null in `environment/gym-anything.json` to use each task's programmatic `verifier.py` instead.
- A reference computer-use agent (`cua-world-agent`, selected via `--agent-import-path gym_anything.integrations.harbor:CuaWorldAgent`) that drives the guest through the runtime API and records ATIF-v1.7 trajectories.
- Standard multimodal CLI agents (Claude Code, Codex, Gemini CLI) can also attempt tasks: the container ships an `AGENTS.md`/`CLAUDE.md` documenting the GUI-control API (observe returns a screenshot file to read; step executes mouse/keyboard actions), so any agent that reads images from disk can drive the VM.
- Uniform protocol budgets on every task: 500 model steps and a 6-hour agent window (the paper's evaluation protocol).

## Generated Task Structure

```
cua-world/
├── {env_name}__{task_id}/
│   ├── task.toml                 # Task configuration (uniform protocol budgets, metadata)
│   ├── instruction.md            # Task instructions for the agent
│   ├── environment/              # Container definition
│   │   ├── Dockerfile            # QEMU-in-container runtime (generic)
│   │   ├── docker-compose.yaml   # KVM passthrough + shared image-cache volume
│   │   └── gym-anything.json     # Task identity / boot config
│   ├── solution/
│   │   └── solve.sh              # Explanatory stub (no scripted oracle; see Notes)
│   └── tests/
│       └── test.sh               # Grades via the in-container verifier pipeline
```

The adapter code directory:

```
adapters/cua-world/
├── README.md
├── adapter_metadata.json
├── parity_experiment.json
├── run_cua-world.yaml
├── pyproject.toml
└── src/cua_world/
    ├── __init__.py
    ├── adapter.py
    ├── main.py
    └── task-template/
        ├── task.toml
        ├── instruction.md
        ├── environment/
        │   ├── Dockerfile
        │   ├── docker-compose.yaml
        │   └── gym-anything.json
        ├── solution/
        │   └── solve.sh
        └── tests/
            └── test.sh
```

> **Note:** `adapter.py` defines `CuaWorldAdapter` with a `run()` method; `main.py` constructs the adapter and calls `run()` through the standard CLI flags.

## Run Evaluation / Harness

Harbor Registry & Datasets makes running adapter evaluation easy and flexible.

### Running with Datasets Registry

Simply run

```bash
# Use the reference computer-use agent and your model
uv run harbor run -d cua-world \
  --agent-import-path gym_anything.integrations.harbor:CuaWorldAgent \
  -m "gemini-3.5-flash"
```

from the harbor root to evaluate on the entire dataset.

> [For adapter creators]: You will need to (1) upload the prepared task directories to https://github.com/laude-institute/harbor-datasets (2) Add your dataset entries to [registry.json](../../../registry.json) following a similar format as others. Only after all the PRs are merged, can you run the above scripts (otherwise the datasets are not yet registered). At development time, use the scripts below to run experiments.

However, if you choose to prepare the task directories locally and/or with custom versions/subsets for evaluation, you may either use `harbor run` or `harbor trial`. Instructions for using the adapter code to prepare task directories are provided in the [Usage](#usage-create-task-directories) session.

### Using Job Configurations

The example configuration file for the adapter is `run_cua-world.yaml` (docker environment, the reference agent, the paper's 500-step budget).

```bash
# From the repository root
# Run a job with the default adapter configuration
uv run harbor run -c adapters/cua-world/run_cua-world.yaml

# Or run a job without configuration yaml but instead with locally prepared dataset path
uv run harbor run -p datasets/cua-world \
  --agent-import-path gym_anything.integrations.harbor:CuaWorldAgent -m "gemini-3.5-flash"

# Resume a previously started job
uv run harbor job resume -p /path/to/jobs/directory
```

Results are saved in the `jobs/` directory by default (configurable via `jobs_dir` in the YAML config).

### Running Individual Trial

For quick testing or debugging a single task:

```bash
# Run a single task with the reference agent and model
uv run harbor trial start -p datasets/cua-world/<task_id> \
  --agent-import-path gym_anything.integrations.harbor:CuaWorldAgent -m "gemini-3.5-flash"
```

Trial outputs are saved in the `trials/` directory by default (configurable via `--trials-dir`).

## Usage: Create Task Directories

```bash
cd adapters/cua-world
uv run cua-world --output-dir ../../datasets/cua-world
```

Available flags:
- `--output-dir` — Directory to write generated tasks (defaults to `datasets/cua-world` at the repo root)
- `--limit` — Generate only the first N tasks
- `--overwrite` — Overwrite existing tasks
- `--task-ids` — Only generate specific task IDs (`{env_name}__{task_id}` form)
- `--split` — `long` (default, the full CUA-World-Long split) or `parity` (the parity subset)
- `--gym-anything-ref` — gym-anything git ref pinned into the generated task images

Tasks are written to `datasets/cua-world/` with one directory per task. Each task follows the structure shown in ["Generated Task Structure"](#generated-task-structure) above.

## Comparison with Original Benchmark (Parity)

Parity experiments are pending coordination with the Harbor team. Because CUA-World-Long episodes are long-horizon (multi-hour budgets across 201 VM-backed tasks), parity will run on a representative subset per the adapter guide's subset mechanism (`--split parity`, published under the `parity` tag). We will select and document the subset (stratified across application domains and guest platforms); the parity plan built on it (agents, models, run counts) is agreed with the team before any runs, and this section plus `parity_experiment.json` will be filled from those results.

| Agent | Model | Metric | Number of Runs | Dataset Size | Original Benchmark Performance | Harbor Adapter Performance |
|-------|-------|--------|------------------|--------------|------------------------------|----------------------------|
| pending | pending | pass@1 | pending | pending | pending | pending |

Reproduction requirements and steps (mandatory):
- Original benchmark side: https://github.com/cmu-l3/gym-anything at the pinned ref; run `gym-anything benchmark <env> --task <task> --agent GeminiQwen3Agent --model <model> --steps 500` with `GEMINI_API_KEY` set.
- Harbor side:
  ```bash
  uv run harbor run -c adapters/cua-world/run_cua-world.yaml
  ```
- Interpretation: `reward` is the benchmark's native reward (sparse 0/1, partial score/100); `passed` and `score` are carried as named metrics. pass@1 compares the `passed` rate.

## Notes & Caveats

- **No scripted oracle solutions.** Tasks are interactive GUI episodes graded by verifiers against live application state; `solution/solve.sh` is an explanatory stub, following the merged OSWorld and TheAgentCompany precedent.
- **KVM required.** The task container boots a guest VM via QEMU; hosts must expose `/dev/kvm` (identical to the OSWorld adapter's requirement). x86_64 hosts only (the guests are x86 images).
- **Shared cache volume.** Create once per host: `docker volume create harbor-gym-anything-cache`. The first boot of an environment provisions its guest image (minutes to tens of minutes); later trials reuse it via copy-on-write overlays.
- **Long budgets.** Every task carries the benchmark's uniform protocol budget: 500 model steps and a 6-hour agent timeout.
- **Grading trust boundary.** The verifier runs in the container, not in the agent-controlled VM, so a compromised guest cannot rewrite its own grades.
- **Grader key.** Default grading uses a VLM judge; export `GEMINI_API_KEY` before running (Harbor passes it to the verifier phase via `[verifier.env]`). Without it, episodes run but grading fails.
- **Platform coverage.** Of the 201 tasks: 168 run Linux guests (images provision automatically from recipes on first boot), 25 run Windows guests and 8 run Android guests. Windows and Android guest images cannot be redistributed for licensing reasons; running those subsets requires supplying the base images into the shared cache volume (the Linux majority needs nothing).
- The task count (201) is the registry's `long_horizon` split; the paper text says 200.

## Installation / Prerequisites

Adapters are managed as standalone uv Python packages. You can add or remove dependencies using `uv add` / `uv remove` from the adapter directory:

```bash
cd adapters/cua-world
uv add datasets  # add a dependency
uv remove datasets  # remove a dependency
```

Environment setup specific to this adapter:
- Docker installed and running, with `/dev/kvm` available on the host
- Harbor installed and working (see main repository README)
- Python environment with dependencies:
  ```bash
  cd adapters/cua-world
  uv sync
  ```
- Dataset-specific steps:
  - `docker volume create harbor-gym-anything-cache` (once per host)
  - `GEMINI_API_KEY` exported: required for the default VLM grading (and for the reference agent when using gemini as the policy); other policy models need their own keys
  - The generated task images pip-install gym-anything from the pinned git ref at build time; no manual dataset download is needed

## Troubleshooting

- `AddTestsDirError` or immediate Docker validation failure: the host lacks `/dev/kvm`, or the `harbor-gym-anything-cache` volume was not created.
- Environment start timeout on a fresh host: the first boot provisions the guest image inside the container; the compose healthcheck allows 40 minutes (`start_period: 2400s`). Subsequent boots are minutes.
- Grading fails or rewards are missing: check `GEMINI_API_KEY` is exported (the default VLM grader needs it).
- Agent timeouts: every task allows 6 hours; override with `--override-timeout-sec` or the job YAML if experimenting with smaller step budgets.
- Disk pressure: guest images and overlays live in the shared volume; prune old overlays with `docker volume` inspection if a host runs many environments.

## Citation

```bibtex
@article{aggarwal2026gymanything,
  title={Gym-Anything: Turn Any Software into a Computer-Use Agent Environment},
  author={Aggarwal, Pranjal and Neubig, Graham and Welleck, Sean},
  year={2026},
  url={https://github.com/cmu-l3/gym-anything}
}
```

## Authors & Contributions

This adapter is developed and maintained by [Pranjal Aggarwal](mailto:pranjal2041@gmail.com) (Carnegie Mellon University).

**Issues and Contributions:**
- Submit Issues and Pull Requests to the main repository
- Follow the project's coding style and commit guidelines

## Acknowledgement

If you used API keys provided via [adapters/parity_api_instructions.md](../parity_api_instructions.md) for running parity experiments, please include the following acknowledgement:

> API inference compute for running parity tests is generously supported by [2077AI](https://www.2077ai.com/) (https://www.2077ai.com/).
