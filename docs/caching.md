# Caching

Gym-Anything has two distinct notions of saved state:

- checkpoint caching during `reset()`
- explicit `save_state()` / `load_state()` snapshot helpers

This page is about checkpoint caching.

## Reset Cache Levels

`GymAnythingEnv.reset()` currently accepts:

- `cache_level="pre_start"`
- `cache_level="post_start"`
- `cache_level="post_task"`

Meaning:

| Level | Checkpoint Created After | Hooks Skipped On Load |
|---|---|---|
| `pre_start` | environment `pre_start` | `pre_start` |
| `post_start` | environment `post_start` | `pre_start`, `post_start` |
| `post_task` | task `pre_task` and task init | all setup hooks before interaction |

`reset_script` or `hooks.reset` still run on every reset.

## Fallback Behavior

The current implementation does not require an exact match first.

If you request:

- `post_task`, it tries `post_task`, then `post_start`, then `pre_start`
- `post_start`, it tries `post_start`, then `pre_start`
- `pre_start`, it tries `pre_start`

That means a lower-level checkpoint can still save time when a higher one has not yet been created.

## Runner Support

| Runner | Current Status |
|---|---|
| `DockerRunner` | fully implemented with `docker commit` |
| `QemuApptainerRunner` | fully implemented with QCOW2 checkpoint files |
| `AVDApptainerRunner` | implemented with checkpoint directories and emulator state |
| `ApptainerDirectRunner` | methods exist but caching is effectively not implemented |
| `LocalRunner` | not supported |

## `use_savevm`

`use_savevm=True` is only meaningful for `QemuApptainerRunner`.

When enabled:

- checkpoint creation uses QEMU snapshot behavior intended to preserve running state
- restore uses `loadvm`
- startup can be much faster than disk-only reboot flows

It is ignored by other runners.

## Checkpoint Identity

Checkpoint names differ by runner, but conceptually:

- `pre_start` and `post_start` are environment-level checkpoints
- `post_task` is task-specific

The current implementations sanitize task IDs when embedding them into checkpoint names or directories.

## Example

```python
env = from_config(
    "benchmarks/environments/zotero_env",
    task_id="create_saved_search",
)

obs = env.reset(
    seed=42,
    use_cache=True,
    cache_level="post_start",
)
```

## What Caching Does Not Guarantee

Checkpointing is runner-specific. In practice:

- it is meant to skip repeated setup work
- it is not a universal promise of identical in-memory execution state
- only the QEMU `savevm` path attempts true fast restore of running VM state

## Separate From `save_state()`

`env.save_state()` and `env.load_state()` are a different mechanism.

They depend on:

- `env_spec.supports_save_restore`
- runner-specific `save_state()` / `load_state()` implementations

Do not treat them as the same feature as `reset(..., use_cache=True)`.
