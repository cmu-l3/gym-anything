# API

## Public Imports

```python
from gym_anything import (
    EnvSpec,
    GymAnythingEnv,
    RemoteGymEnv,
    TaskSpec,
    from_config,
    get_runner_compatibility,
    get_runner_compatibility_matrix,
    make,
    query_vlm,
)
```

## Constructors

### `from_config(env_dir, task_id=None) -> GymAnythingEnv`

Loads:

- `env.json` or `env.yaml` from `env_dir`
- optionally `tasks/<task_id>/task.json` or `task.yaml`
- a built-in preset if the env file contains `base`

Behavior when `task_id` is omitted:

- if exactly one task file exists, it is selected
- otherwise the environment is created without a task

Example:

```python
env = from_config(
    "benchmarks/cua_world/environments/zotero_env",
    task_id="create_saved_search",
)
```

### `make(env, task=None, overrides=None) -> GymAnythingEnv`

Accepted input forms:

- file path
- dict
- dataclass instance

`overrides` are applied after loading. The current override behavior is shallow except for a few nested dataclass sections such as `resources`, `security`, `recording`, and `apptainer`.

## `GymAnythingEnv`

### `reset(seed=None, use_cache=False, cache_level="pre_start", use_savevm=False)`

Starts the runner, prepares an episode directory, runs hooks, and returns the first observation.

Important details:

- valid cache levels are `pre_start`, `post_start`, and `post_task`
- cache lookup falls back to lower levels when a requested checkpoint is missing
- `reset_script` runs on every reset even when checkpoints are used
- `hooks["reset"]` is used only if `reset_script` is absent
- `use_savevm=True` only matters for `QemuApptainerRunner`

### `step(actions, wait_between_actions=0.2, mark_done=False)`

Executes a batch of low-level actions and returns:

```python
observation, reward, done, info
```

Important details from the current implementation:

- `actions` should be a list of action dicts
- a single dict is accepted and wrapped internally
- the environment waits `wait_between_actions` only between actions in the batch
- after the batch, the runtime currently applies an unconditional `2` second settle wait
- if `env_spec.synchronous` is true, it then also waits `step_cycle_ms / 1000`
- `mark_done=True` triggers `post_task`, a final screenshot, and verification

### `close()`

Stops the runner and finalizes summary artifacts.

If you close without calling `step(..., mark_done=True)`, the runtime still runs `post_task`, captures final artifacts, and executes verification before shutdown. Use `mark_done=True` when you want the verifier result back in the `step()` return value before closing the environment.

### `capture_observation()`

Captures the current observation without advancing the episode.

### `apply_post_reset_setup(setup_code="auto", steps=None, env_dir=None)`

Applies the standardized post-reset setup routine used by the reference harnesses and worker reset policies.

### `get_compatibility_profile()`

Returns the active runner's compatibility record as a dictionary.

Use this when a deployment or benchmark flow needs to branch on supported behavior instead of inferring it from runner class names.

For the static contract independent of an instantiated env, use:

```python
get_runner_compatibility("docker")
get_runner_compatibility_matrix()
```

### File Operations

```python
env.copy_to_env("/host/file.txt", "/tmp/file.txt")
env.copy_from_env("/tmp/result.json", "/host/result.json")
```

### State Snapshot Helpers

```python
snapshot = env.save_state()
env.load_state(snapshot)
```

Current behavior:

- only meaningful when `supports_save_restore` is set to `snapshot` or `custom`
- separate from checkpoint caching
- runner-specific implementation details vary

### Recording Controls

```python
env.pause_recording()
env.resume_recording()
```

These only affect continuous FFmpeg recording. The per-step screenshot path used in observations is separate and continues to be captured through `capture_observation()`.

If live recording is unavailable on the current runner, `close()` still attempts to assemble `recording.mp4` from saved step screenshots when host `ffmpeg` is available.

## Observation Format

The core observation builder currently recognizes these modalities:

- `rgb_screen`
- `audio_waveform`
- `ui_tree`

Typical screen observation:

```python
{
    "screen": {
        "path": ".../frame_00000.png",
        "resolution": [1920, 1080],
        # only when inline=true:
        "png_b64": "..."
    }
}
```

Typical audio observation:

```python
{
    "audio": {
        "rate": 16000,
        "channels": 1,
        "num_samples": 3200,
        "s16le_b64": "..."
    }
}
```

Typical UI tree observation:

```python
{
    "ui_tree": {
        "text": "..."
    }
}
```

## Canonical Action Shape

The current runners primarily expect nested action dicts like these:

```python
{"mouse": {"left_click": [x, y]}}
{"mouse": {"right_click": [x, y]}}
{"mouse": {"double_click": [x, y]}}
{"mouse": {"left_click_drag": [[x1, y1], [x2, y2]]}}
{"mouse": {"scroll": 3}}

{"keyboard": {"text": "hello"}}
{"keyboard": {"keys": ["ctrl", "s"]}}
```

Runner-specific extensions also exist:

- `voice` is only handled by `DockerRunner`
- `api_call` is only meaningfully supported on certain Docker-based flows

The older flat action style shown in some historical docs is not the runner-side canonical format.

## Reward Behavior

The current runtime behavior is:

- `sparse`: final reward is `1.0` if verifier passed, otherwise `0.0`
- `dense`: per-step reward comes from `reward_shaping`
- `partial`: final reward is the verifier `score` on a `0-100` scale
- `rubric`: final reward is the verifier `score` on a `0-100` scale
- `continuous`: final reward is the verifier `score` normalized to `0.0-1.0`

## `RemoteGymEnv`

`RemoteGymEnv` mirrors much of the local interface over HTTP:

```python
remote = RemoteGymEnv.from_config(
    remote_url="http://worker-host:5000",
    env_dir="benchmarks/cua_world/environments/zotero_env",
    task_id="create_saved_search",
)
```

Important differences:

- remote `reset()` exposes `seed`, `use_cache`, `cache_level`, and `use_savevm`
- worker reset defaults to the same `core` behavior as local reset
- optional worker-side baseline setup is available through `worker_reset_policy="baseline_setup"`
- remote file copy methods operate relative to the remote server's filesystem
