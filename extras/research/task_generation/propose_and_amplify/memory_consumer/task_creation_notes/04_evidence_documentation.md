> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Evidence Documentation Guide

## Overview

Evidence documentation proves that tasks are correctly implemented and working. This is essential for:
- **Quality assurance**: Verifying tasks work before release
- **Debugging**: Identifying issues when things go wrong
- **Review**: Allowing others to validate task design
- **Audit trail**: Documenting what was tested and when

---

## Evidence Directory Structure

Evidence lives **inside** each environment's directory, not at the repo root:

```
benchmarks/cua_world/environments/<env_name>/
├── evidence_docs/
│   ├── <task_name>_screenshot.png      # Task start state screenshot
│   ├── <task_name>_evidence.json       # Database/system verification
│   └── ... (one set per task)
├── env.json
├── scripts/
└── tasks/
```

```
benchmarks/cua_world/environments/<env_name>/
└── evidence_docs/
    ├── <task_name_1>_screenshot.png
    ├── <task_name_1>_evidence.json
    ├── <task_name_2>_screenshot.png
    ├── <task_name_2>_evidence.json
    └── ...
```

---

## What Evidence to Collect

### 1. Task Start Screenshot

**Purpose**: Prove the environment starts in the correct state.

**Should show**:
- Application is running (Firefox with OpenEMR, etc.)
- Login page or expected starting point
- Desktop is ready for agent interaction

**How to capture**:
```python
# In test script
env._runner.exec_capture('DISPLAY=:1 scrot /tmp/task_start_screenshot.png')
env._runner.copy_from('/tmp/task_start_screenshot.png', f'benchmarks/cua_world/environments/{env_name}/evidence_docs/{task_name}_screenshot.png')
```

### 2. Database Evidence JSON

**Purpose**: Prove required data exists and is correct.

**Should include**:
- Patient/target data verification
- Baseline counts (appointments, prescriptions, etc.)
- Relevant conditions, diagnoses, related data
- Docker/system status

**Example evidence JSON**:
```json
{
  "task": "<task_name>",
  "timestamp": "2026-01-30 14:30:00",
  "checks": {
    "target_entity": "<description of what was verified>",
    "initial_state": "<description of baseline>",
    "service_status": "<healthy/running>"
  },
  "setup_files_created": [
    "/tmp/initial_<something>",
    "/tmp/task_start_timestamp",
    "/tmp/task_start_screenshot.png"
  ]
}
```

### 3. Export Script Output

**Purpose**: Verify export script runs without errors.

**Should capture**:
- Full export script output
- Resulting JSON file contents
- Any error messages

---

## Evidence Collection Script Template

```python
#!/usr/bin/env python3
"""Evidence collection for [Environment] tasks."""

import sys
import os
import time
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + '/..')
from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/cua_world/environments/<env_name>/evidence_docs'


def collect_evidence(env, task_name):
    """Collect comprehensive evidence for a task."""
    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "checks": {}
    }

    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    # 1. Verify critical data
    print(f"\n[DATABASE] Verifying data for {task_name}...")

    # Query patient data
    patient_data = env._runner.exec_capture(
        'docker exec db-container mysql -u user -ppass db -e "SELECT * FROM patients WHERE pid=X"'
    )
    evidence["checks"]["patient_data"] = patient_data.strip()
    print(f"Patient: {patient_data}")

    # Query conditions/diagnoses
    conditions = env._runner.exec_capture(
        'docker exec db-container mysql -u user -ppass db -e "SELECT * FROM conditions WHERE pid=X"'
    )
    evidence["checks"]["conditions"] = conditions.strip()
    print(f"Conditions: {conditions}")

    # 2. Verify system status
    print("\n[SYSTEM] Checking services...")
    docker_status = env._runner.exec_capture('docker ps --format "{{.Names}}: {{.Status}}"')
    evidence["checks"]["docker_status"] = docker_status.strip()
    print(docker_status)

    # 3. Verify setup files
    print("\n[SETUP] Checking task setup files...")
    setup_files = env._runner.exec_capture('ls -la /tmp/initial_* /tmp/task_start_* 2>&1')
    evidence["checks"]["setup_files"] = setup_files.strip()
    print(setup_files)

    # 4. Take screenshot
    print("\n[SCREENSHOT] Capturing screen...")
    env._runner.exec_capture('DISPLAY=:1 scrot /tmp/evidence_screenshot.png')
    time.sleep(0.5)

    screenshot_path = f'{EVIDENCE_DIR}/{task_name}_screenshot.png'
    try:
        env._runner.copy_from('/tmp/task_start_screenshot.png', screenshot_path)
        evidence["screenshot"] = screenshot_path
        print(f"Screenshot saved: {screenshot_path}")
    except Exception as e:
        print(f"Screenshot error: {e}")

    # 5. Save evidence JSON
    evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
    with open(evidence_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    print(f"Evidence saved: {evidence_path}")

    return evidence


def test_task(task_name):
    """Test a single task and collect evidence."""
    print(f"\n{'='*60}")
    print(f"TESTING: {task_name}")
    print('='*60)

    env = from_config("benchmarks/cua_world/environments/<env_name>", task_id=task_name)

    try:
        obs = env.reset(seed=42, use_cache=False)
        print(f"Environment ready - VNC: {env._runner.vnc_port}")

        evidence = collect_evidence(env, task_name)

        # Test export script
        print("\n[EXPORT] Testing export script...")
        export_out = env._runner.exec_capture(f'bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1')
        print(export_out[-1000:])

        if "Export Complete" in export_out:
            print("[PASS] Export script completed")
        else:
            print("[WARN] Export may have issues")

        return evidence

    finally:
        env.close()


if __name__ == "__main__":
    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    tasks = [
        "task_name_1",
        "task_name_2",
        # Add all tasks
    ]

    for task in tasks:
        test_task(task)

    print(f"\nEvidence saved to: {EVIDENCE_DIR}/")
```

---

## Evidence Review Checklist

When reviewing evidence for a task:

### Screenshot Review
- [ ] Application is visible and running
- [ ] Correct starting page/state shown
- [ ] No error dialogs or popups blocking
- [ ] Desktop is responsive (not frozen/loading)

### Database Evidence Review
- [ ] Target patient/entity exists with correct ID
- [ ] Required related data exists (conditions, medications, etc.)
- [ ] Baseline counts are recorded
- [ ] All IDs match task.json metadata

### Setup Files Review
- [ ] `/tmp/initial_*` files created
- [ ] `/tmp/task_start_timestamp` exists
- [ ] `/tmp/task_start_screenshot.png` captured
- [ ] No error messages in setup output

### Export Script Review
- [ ] Script completes with "Export Complete" message
- [ ] JSON file created at expected location
- [ ] JSON is valid and parseable
- [ ] All expected fields present in JSON

---

## Common Evidence Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| Screenshot not captured | File not found | Check DISPLAY=:1 is set, scrot installed |
| Database query fails | Empty result or error | Verify Docker container running, credentials correct |
| Setup files missing | ls shows "No such file" | Check setup_task.sh has execute permission |
| JSON parse error | Malformed JSON | Check export_result.sh for escaping issues |
| Wrong patient data | IDs don't match | Verify patient exists, check pid in query |

---

## Automating Evidence Collection

For environments with multiple tasks, create a comprehensive test script:

```python
# test_all_<env>_tasks.py

TASKS = [
    "task1",
    "task2",
    "task3",
]

all_results = {}
for task in TASKS:
    result = test_task(task)
    all_results[task] = result

# Summary report
print("\n" + "="*60)
print("EVIDENCE COLLECTION SUMMARY")
print("="*60)
for task, evidence in all_results.items():
    checks_passed = sum(1 for v in evidence['checks'].values() if v)
    print(f"{task}: {checks_passed} checks verified")

print(f"\nAll evidence in: {EVIDENCE_DIR}/")
```

---

## Framework Verifier Result Latency: Read from `summary.json`, Not `info["verifier"]`

When writing evidence collection scripts that call `env.step([], mark_done=True)` to immediately trigger verification, be aware that verification finalization is **asynchronous**:

- `env.step()` may return before the verifier and hooks complete
- `info["verifier"]` may be `None` (the key exists but points to `None`)
- Calling `.get("passed")` on `None` raises `AttributeError`; calling it on a missing key returns a default silently — both hide the real result

**Unreliable pattern (do not use):**
```python
obs2, reward, done, info = env.step([], mark_done=True)
vr = info.get("verifier", {})      # may return None, not {}
passed = vr.get("passed")           # AttributeError if vr is None
```

**Reliable pattern — read from `summary.json` after a brief wait:**
```python
obs2, reward, done, info = env.step([], mark_done=True)
time.sleep(5)  # allow finalization to complete

# Read from episode artifacts directory (ground truth)
artifacts_dir = "benchmarks/cua_world/environments/<env_name>/artifacts"
episodes = sorted([d for d in os.listdir(artifacts_dir) if d.startswith("episode_")])
verifier_result = {}
if episodes:
    summary_path = os.path.join(artifacts_dir, episodes[-1], "summary.json")
    if os.path.exists(summary_path):
        with open(summary_path) as f:
            summary = json.load(f)
        verifier_result = summary.get("verifier", {})

# Fall back to info dict only if summary.json is unavailable
info_vr = info.get("verifier") or {}
if info_vr.get("passed") is not None:
    verifier_result = info_vr

passed = verifier_result.get("passed")
score = verifier_result.get("score")
```

`summary.json` is written by the framework after all `post_task` hooks and verifier calls complete, making it the authoritative record of the episode result. The episode directory is named `episode_<timestamp>` and is located in `benchmarks/cua_world/environments/<env_name>/artifacts/` by default.

---

## Version Control

Evidence files should be:
- **Committed**: Evidence JSON files (small, human-readable)
- **Not committed**: Large screenshots (add to .gitignore if needed)
- **Documented**: Include evidence collection instructions in README

Example .gitignore:
```gitignore
# Keep JSON evidence, exclude large screenshots
evidence_docs/**/*.png
!evidence_docs/**/README.md
```

Or keep screenshots for critical verification:
```gitignore
# Keep all evidence
!evidence_docs/
```
