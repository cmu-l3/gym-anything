# CLI And Entry Points

There are three different command families in this repo:

- the core package CLI
- reference evaluation harnesses
- remote service binaries

## Core Package CLI

The public package CLI lives at `src/gym_anything/cli.py`.

Use it with:

```bash
PYTHONPATH=src python -m gym_anything.cli --help
```

Current subcommands:

- `verify`
- `compatibility`
- `doctor`
- `validate`
- `run`

### Verify

```bash
PYTHONPATH=src python -m gym_anything.cli verify spec \
  benchmarks/cua_world/environments/zotero_env \
  --task create_saved_search
```

Verification subcommands:

- `verify spec`: parse specs, validate supported runtime fields, and check task-local references such as verifier modules and hook-side script files
- `verify corpus`: run spec verification across a benchmark root
- `verify task`: execute `reset -> mark_done` and confirm that the task verifier actually runs

Use `verify` as the canonical release-readiness surface.

### Validate

```bash
PYTHONPATH=src python -m gym_anything.cli validate \
  benchmarks/cua_world/environments/zotero_env \
  --task create_saved_search
```

`validate` is now the compatibility alias for spec verification.

### Compatibility

```bash
PYTHONPATH=src python -m gym_anything.cli compatibility
```

Use this to inspect the release-facing runner contract instead of inferring support from scattered docs.

Examples:

```bash
PYTHONPATH=src python -m gym_anything.cli compatibility --runner docker
PYTHONPATH=src python -m gym_anything.cli compatibility --runner qemu --json
```

This command reports the supported differences across runners for:

- recording
- checkpoint caching
- `use_savevm`
- `user_accounts`

### Doctor

```bash
PYTHONPATH=src python -m gym_anything.cli doctor
```

Use this to check system prerequisites before debugging a runner failure.

Examples:

```bash
PYTHONPATH=src python -m gym_anything.cli doctor --runner docker
PYTHONPATH=src python -m gym_anything.cli doctor --runner qemu
PYTHONPATH=src python -m gym_anything.cli doctor --verification-root benchmarks/cua_world/environments
```

This command reports:

- runner-specific system binaries and daemon availability
- optional host tools such as `ffmpeg`
- optional static verifier-import scan results when `--verification-root` is provided

### Run

```bash
PYTHONPATH=src python -m gym_anything.cli run \
  benchmarks/cua_world/environments/zotero_env \
  --task create_saved_search \
  --steps 3
```

Current behavior:

- resets the environment
- loops for a fixed number of steps
- uses empty actions

This is best treated as a smoke test, not as a serious agent evaluation tool.

## Reference Evaluation Harnesses

### Single Task

```bash
python -m baselines.evaluation.run_single --help
```

This script is the main research harness for running one agent on one task.

Important caveats:

- it applies optional environment-specific setup behavior through `baselines.evaluation.setup`

### Batch

```bash
python -m baselines.evaluation.run_batch --help
```

This script shells out to `run_single` repeatedly.

It is useful for experiments, but it is not a carefully isolated orchestration layer.

The benchmark selection surface is data-driven:

- split definitions come from `benchmarks/cua_world/splits/*_split.json`
- `--surface raw` uses the full declared split data
- `--surface verified` filters those splits to the verifier-backed task set from `benchmarks/cua_world/splits/verified.json`

## Remote Services

### Master

```bash
python -m services.master.app --help
```

### Worker

```bash
python -m services.worker.app --help
```

### Dashboard

```bash
python -m services.dashboard.app --help
```

These support distributed environment creation and proxying. See [Distributed Services](distributed-services.md).

## Artifact Locations

Artifacts depend on how you run:

- core env usage writes into `recording.output_dir`
- many baseline runs write under `all_runs/...`

Do not assume every path will contain the same file set. The reliable core artifacts are:

- screenshot frames
- `traj.jsonl`
- `summary.json`

`recording.mp4` appears when live recording succeeded or when screenshot-to-video assembly succeeded on close.
