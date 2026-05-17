> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Repository Structure for Task Creation

## Overview

Before creating tasks, you must understand the repository structure and how tasks integrate with the Gym-Anything framework. This document maps out what you need to know.

---

## Directory Structure

```
gym-anything/
├── src/gym_anything/                # Core framework — importable as `gym_anything`
│   ├── api.py                       # from_config(), make()
│   ├── env.py                       # GymAnythingEnv class
│   ├── specs.py                     # EnvSpec, TaskSpec dataclasses
│   ├── contracts.py                 # SessionInfo, RunnerRuntimeInfo
│   ├── verification/                # Verification runner
│   │   └── runner.py                # Calls verifier.py
│   └── runtime/runners/             # VM/container runners (qemu_apptainer, docker, …)
│
├── benchmarks/cua_world/
│   ├── environments/                # ALL ENVIRONMENTS LIVE HERE
│   │   └── <env_name>/              # One folder per environment
│   │       ├── env.json             # Environment specification
│   │       ├── scripts/             # Installation/setup scripts
│   │       ├── config/              # Configuration files
│   │       ├── utils/               # Utility scripts
│   │       ├── evidence_docs/       # Test evidence for this env
│   │       │   ├── <task>_screenshot.png
│   │       │   └── <task>_evidence.json
│   │       └── tasks/               # TASKS LIVE HERE
│   │           └── <task_name>/     # One folder per task
│   │               ├── task.json    # Task specification
│   │               ├── README.md    # Task documentation
│   │               ├── setup_task.sh    # Pre-task setup
│   │               ├── export_result.sh # Post-task data export
│   │               └── verifier.py  # Verification logic
│   ├── splits/                      # TASK REGISTRY lives here as JSON files
│   │   ├── <env_name>_split.json    # Per-env train/test/all task lists
│   │   └── verified.json            # Cross-env list of verified tasks
│   └── registry/                    # Loader helpers (splits.py)
│
├── extras/research/
│   ├── software_as_env/creation_audit/memory/env_creation_notes/   # Env creation docs
│   └── task_generation/propose_and_amplify/memory/task_creation_notes/  # Task creation docs (this folder)
```

> **Note:** `ask_cua.py` (the Codex-side VLM helper referenced elsewhere in
> these notes) is not currently shipped in the repo — provide your own or
> use the `visual_grounding` MCP tool from
> `extras/research/software_as_env/creation_audit/mcp/`.

---

## Key Files to Understand

### 1. env.json (Environment Level)

Defines the environment. Tasks inherit from this.

```json
{
  "id": "openemr_env@0.1",
  "preset": "ubuntu-gnome-systemd_highres",
  "net": true,
  "resources": {"cpu": 4, "mem_gb": 8},
  "mounts": [
    {"src": "scripts", "dst": "/workspace/scripts"},
    {"src": "tasks", "dst": "/workspace/tasks"}
  ],
  "hooks": {
    "pre_start": "/workspace/scripts/install_docker.sh",
    "post_start": "/workspace/scripts/setup_openemr.sh"
  }
}
```

**Key points:**
- `mounts` copies local folders into the VM at `/workspace/`
- `hooks` run scripts at different lifecycle stages
- Tasks can access `/workspace/tasks/<task_name>/` inside the VM

### 2. task.json (Task Level)

Defines a specific task within an environment.

```json
{
  "id": "<task_name>@1",
  "version": "1.0",
  "env_id": "<env_name>@0.1",
  "description": "Full task description here — state the goal and end state, not the UI path.",
  "difficulty": "hard",
  "init": {
    "timeout_sec": 480,
    "max_steps": 60
  },
  "hooks": {
    "pre_task": "/workspace/tasks/<task_name>/setup_task.sh",
    "post_task": "/workspace/tasks/<task_name>/export_result.sh"
  },
  "metadata": {
    "target_id": 123,
    "target_name": "...",
    "expected_outcome": "..."
  },
  "success": {
    "mode": "program",
    "spec": {
      "program": "verifier.py::verify_<task_name>"
    }
  }
}
```

**Key points:**
- `hooks.pre_task`: Runs before agent starts (setup initial state)
- `hooks.post_task`: Runs after agent finishes (export data for verification)
- `metadata`: Store ground truth values for verification
- `success.spec.program`: Points to verifier function

**Valid hooks fields** — `TaskHooks` only accepts exactly three fields: `pre_task`, `post_task`, and `pre_task_timeout`. Do not add `post_task_timeout` or any other invented field — it will raise a `TypeError: TaskHooks.__init__() got an unexpected keyword argument` at `env.reset()` time.

### 3. Task Registry — `benchmarks/cua_world/splits/<env_name>_split.json`

> **Note:** older notes may refer to a top-level `constants.py` with an
> `ENV_TASK_SPLITS` dict — that file no longer exists. The registry is now
> a directory of JSON files loaded by
> `benchmarks/cua_world/registry/splits.py`. Auto-discovery from
> `benchmarks/cua_world/environments/<env_name>/tasks/*` happens for free,
> so tasks are discoverable even before you write a split file. You only
> need to author a split file when you want explicit `train` / `test`
> partitions or other named splits.

**To register an env with explicit splits**, drop a single JSON file at
`benchmarks/cua_world/splits/<env_name>_split.json`:

```json
{
  "env_folder": "benchmarks/cua_world/environments/<env_name>",
  "train_ratio": 0.8,
  "train_tasks": [
    "task_name_1", "task_name_2", "task_name_3"
  ],
  "test_tasks": [
    "task_name_4", "task_name_5"
  ],
  "all_tasks": [
    "task_name_1", "task_name_2", "task_name_3",
    "task_name_4", "task_name_5"
  ]
}
```

Optional fields:
- `all_tasks`: explicit ordering for the `all` split. If omitted, the
  registry uses `train_tasks + test_tasks` deduped, and falls back to
  on-disk discovery.
- `additional_splits`: a `{<split_name>: [task_ids…]}` map for custom
  named splits beyond `train` / `test` / `all`.
- Any top-level `<name>_tasks` array (e.g. `easy_tasks`,
  `hard_tasks`) is also recognized as an additional split.

**Cross-env "verified" set.** The file `benchmarks/cua_world/splits/verified.json`
holds the curated verified tasks per env in a `by_environment` map; the
registry auto-exposes those as the `verified` split.

**Key points:**
- A new env doesn't *require* a split file — all on-disk tasks are exposed
  as `all` / `train` automatically. Add a split file only when you want a
  curated `test` partition.
- Verify with:
  ```python
  from benchmarks.cua_world.registry import (
      get_tasks_for_environment,
      load_environment_task_splits,
  )
  print(get_tasks_for_environment("my_env", split="test"))
  print(load_environment_task_splits()["my_env"])
  ```
- Or from the CLI: `gym-anything list --verbose`.

---

## Task File Details

### setup_task.sh

**Purpose**: Run BEFORE the agent starts. Establishes initial state.

**Must do:**
1. Verify required data exists (patient, file, etc.)
2. Record baseline counts (appointments, prescriptions, etc.)
3. Save task start timestamp
4. Ensure application is running and ready
5. Take initial screenshot

**Must NOT do:**
- NEVER generate synthetic data. No `np.random`, no `faker`, no programmatic data fabrication.
- All data must already exist (from post_start hooks, from real data files shipped in `data/`, or from the environment's database).
- setup_task.sh may copy, move, configure, or insert real data into the right places — but it must NOT create fake data from scratch.

**Template:**
```bash
#!/bin/bash
# Setup script for [Task Name]

echo "=== Setting up [Task Name] ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Seed the starting state for this task using REAL data.
# All data must come from real sources (database, real files in data/, etc.)
# NEVER generate synthetic data here — no np.random, no faker, no data fabrication.
# Hard/very_hard tasks: set up a realistic messy state the agent must work through.
# This may mean inserting multiple records with errors, creating conflicting state,
# or populating data across multiple entities — NOT just verifying one target exists.

# Record baseline state (CRITICAL for adversarial robustness)
# What you snapshot depends on what the task requires — could be counts, IDs,
# file hashes, or the full state of multiple entities.
# Example (adapt to your task):
# INITIAL_STATE=$(query_something)
# echo "$INITIAL_STATE" > /tmp/initial_state

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure app is running
# su - ga -c "DISPLAY=:1 <app_launch_command> &"
# sleep <appropriate_wait>

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
```

### export_result.sh

**Purpose**: Run AFTER the agent finishes. Extract data for verification.

**Must do:**
1. Query current state from database/filesystem
2. Compare against baseline
3. Extract relevant fields
4. Save as JSON to `/tmp/<task_name>_result.json`

**Template:**
```bash
#!/bin/bash
# Export script for [Task Name]

echo "=== Exporting [Task Name] Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the current state of everything the verifier needs to check.
# For hard/very_hard tasks this may mean querying multiple entities,
# checking multiple features of the app, and capturing state across
# several independent subtasks — not just counting one type of record.

# Get baseline (if applicable)
# INITIAL_STATE=$(cat /tmp/initial_state 2>/dev/null || echo "0")

# Query current state for each subtask
# SUBTASK_1_STATE=$(query_something)
# SUBTASK_2_STATE=$(query_something_else)
# ...

# Create result JSON with all subtask states
cat > /tmp/task_result.json << EOF
{
    "target_id": $TARGET_ID,
    "subtask_1_complete": $SUBTASK_1_DONE,
    "subtask_2_complete": $SUBTASK_2_DONE,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "=== Export Complete ==="
```

### verifier.py

**Purpose**: Read exported JSON and determine pass/fail.

**Must do:**
1. Copy result JSON from VM using `copy_from_env`
2. Parse and validate data
3. Apply multi-criterion scoring
4. Return structured result

**Template:**
```python
#!/usr/bin/env python3
"""Verifier for [Task Name]"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify task completion.

    Scoring (100 points):
    - Criterion 1: X points
    - Criterion 2: Y points
    - ...

    Pass threshold: Z points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_id = metadata.get('target_id')

    try:
        # Copy result from VM
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        # CRITICAL: Wrong target check (score=0 if wrong)
        if result.get('target_id') != expected_id:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Wrong target! Expected id={expected_id}"
            }

        # Each criterion below should verify a DIFFERENT independent subtask.
        # Do not use multiple criteria to describe different fields of the same
        # single action — that is still a single-action task.

        # Subtask 1: [description]
        if result.get('subtask_1_complete'):
            score += 30
            feedback_parts.append("Subtask 1 complete")

        # Subtask 2: [description]
        # ... more subtasks ...

        passed = score >= 70  # Pass threshold

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}
```

---

## Utility Scripts

### task_utils.sh

Common utilities sourced by task scripts. Located at `/workspace/scripts/task_utils.sh`.

**Key functions:**
```bash
# Query OpenEMR database
openemr_query() {
    docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "$1"
}

# Take screenshot
take_screenshot() {
    DISPLAY=:1 scrot "$1" 2>/dev/null || true
}

# Wait for window
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    # ... implementation ...
}
```

---

## File Permissions

**CRITICAL**: All `.sh` files must be executable!

```bash
# After creating scripts, always run:
chmod +x benchmarks/cua_world/environments/<env_name>/tasks/<task_name>/*.sh
```

If scripts aren't executable, the hook will fail silently with exit code 126.

---

## Testing Your Task

```python
from gym_anything.api import from_config

# Load environment with your task
env = from_config("benchmarks/cua_world/environments/<env_name>", task_id="<task_name>")

# Start environment (runs pre_start, post_start, pre_task hooks)
# Use cached boot for faster iteration during development:
obs = env.reset(seed=42, use_cache=True, cache_level="pre_start", use_savevm=True)

# Get connection info
ssh_port = env._runner.ssh_port
vnc_port = env._runner.vnc_port

# Execute commands in VM
output = env._runner.exec_capture('ls -la /tmp/')

# Copy files from VM
env._runner.copy_from('/tmp/result.json', './local_result.json')

# Run verification (runs post_task hook, then verifier)
# IMPORTANT: env.verify() does NOT exist. Use env.step() with mark_done=True:
# NOTE: env.step() returns a 4-tuple, NOT 5. There is no 'truncated' value.
obs, reward, done, info = env.step([], mark_done=True)
result = info.get("verifier", {})
print(f"Passed: {result['passed']}, Score: {result['score']}")

# Cleanup
env.close()
```
