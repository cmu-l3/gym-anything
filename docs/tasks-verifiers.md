# Tasks And Verifiers

## Task Layout

Canonical task layout:

```text
benchmarks/environments/<env_name>/tasks/<task_id>/
├── task.json
├── verifier.py
├── setup_task.sh        optional
├── export_result.sh     optional
└── metadata/            optional task-local metadata
```

Common runtime roles:

- `task.json`: runtime-recognized task spec plus extra corpus metadata
- `setup_task.*`: task setup before agent interaction
- `export_result.*`: task export before verification
- `verifier.py`: host-side verification logic

## Runtime Task Fields

The core loader currently preserves these task fields:

- `id`
- `env_id`
- `version`
- `description`
- `name`
- `difficulty`
- `natural_language`
- `deps`
- `tags`
- `init`
- `hooks`
- `success`
- `metadata`
- `extras`

`extras` contains any unmodeled top-level task keys that were present in `task.json` but do not yet have first-class dataclass fields.

## Task Lifecycle

During `reset()`:

1. environment hooks run
2. task `pre_task` runs if present
3. task `init.init_script` runs if present
4. Windows-only `init.init_pyautogui` actions run if present

During finalization with `mark_done=True`:

1. task `post_task` runs if present
2. the runtime waits briefly
3. `post_verification.png` is captured
4. the verifier runs on the host

## Verification Modes

### `program`

Most tasks use this mode.

`success.spec.program` accepts:

- `verifier.py::function_name`
- `package.module:function_name`

### `image_match`

Uses FFmpeg SSIM comparison between an observed image and a target image.

### `multi`

Runs program verification first and falls back to image matching if the program verifier does not decide.

## Current Corpus Reality

In this checkout:

- program verifiers dominate the corpus
- `image_match` and `multi` are rare relative to `program`
- the verifier-backed supported task surface is published in `benchmarks/splits/verified.json`

## Program Verifier Contract

A verifier function is called as:

```python
def verify_task(traj, env_info, task_info):
    ...
```

### `traj`

The current verifier loader builds a trajectory dict containing:

- `steps`: parsed `traj.jsonl` events
- `episode_dir`
- `frames`: sorted `frame_*.png` paths
- `final_screenshot`
- `post_verification_screenshot`
- `first_frame`
- `last_frame`
- `step_frames`: map of step index to frame path

### `env_info`

Current helper keys:

- `env_id`
- `episode_dir`
- `copy_from_env`
- `copy_to_env`
- `exec_capture`
- `query_vlm`
- `sample_trajectory_frames`
- `get_final_screenshot`
- `get_first_screenshot`

Depending on the runner, compatibility keys such as `container` may also appear.

### `task_info`

Current task info payload:

- `task_id`
- `metadata`
- `task_spec` as a dict

## Example Verifier

```python
import json


def verify_task(traj, env_info, task_info):
    local_path = traj["episode_dir"] + "/result.json"
    copy_from_env = env_info["copy_from_env"]
    copy_from_env("/tmp/result.json", local_path)

    with open(local_path, "r", encoding="utf-8") as f:
        result = json.load(f)

    passed = result.get("saved_search_name") == task_info["metadata"]["search_name"]
    return {
        "passed": passed,
        "score": 100 if passed else 0,
    }
```

## Image Match Semantics

Current behavior:

- `observed` defaults to `final.png`
- relative observed paths resolve under the episode directory
- relative target paths resolve under the task root first, then env root
- FFmpeg SSIM output is parsed and scaled to a `0-100` score for the verifier report

## Reward Semantics

### Sparse

The environment loop converts verifier success to:

- `1.0` when `passed` is truthy
- `0.0` otherwise

### Dense

If `reward_type == "dense"` and `reward_shaping` is configured:

- the reward function is loaded dynamically
- it is called once per step

### Partial And Rubric

If `reward_type` is `partial` or `rubric`:

- the final verifier `score` is returned directly
- the expected score scale is `0-100`

### Continuous

If `reward_type == "continuous"`:

- the final verifier `score` is normalized to `0.0-1.0`
- verifier scores are still expected to be on a `0-100` scale

## Authoring Recommendations

- Export machine-checkable state in `post_task` rather than scraping complex UI state inside the verifier.
- Put expected values in `task.json -> metadata`, not inside verifier constants.
- Use 2-4 independent checks when possible.
- Treat VLM queries as an extra signal, not as the only correctness signal.
- If a task relies on `post_task`, always finalize with `mark_done=True` before closing the environment.
