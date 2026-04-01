# Specs

This page documents the fields the current loader actually recognizes in `EnvSpec` and `TaskSpec`.

That is narrower than the full set of keys you may see in benchmark JSON files.

## Important Distinction

Many files in `benchmarks/environments/` contain extra metadata such as:

- environment- or task-specific custom keys

The loader is permissive, but only fields modeled in `src/gym_anything/specs.py` have typed runtime behavior. Unmodeled task keys are preserved in `TaskSpec.extras`.

If you need a field in runtime code, make sure it exists in the dataclass and in the consuming logic. Do not assume that putting a key in JSON makes it available on `env.env_spec` or `env.task_spec`.

## Environment Spec

`EnvSpec` is loaded from `env.json` or `env.yaml`.

### Metadata

- `id`
- `version`
- `description`
- `category`
- `authors`
- `licence`
- `upstream_url`
- `tags`

### Runtime

- `base`
- `image`
- `dockerfile`
- `entrypoint`
- `apptainer`
- `resources`
- `mounts`
- `apks`
- `user_accounts`

### Interfaces

- `observation`
- `action`
- `synchronous`
- `step_cycle_ms`

### Reset and State

- `reset_script`
- `deterministic`
- `supports_save_restore`
- `save_paths`

### Security and Connectivity

- `security`
- `recording`
- `vnc`
- `ssh`
- `adb`
- `avd`
- `diagnostics`

### Platform Hints

- `os_type`
- `runner`
- `display_backend`
- `input_backend`
- `audio_backend`
- `skip_display_audio_bootstrap`

### Hooks

- `hooks.pre_start`
- `hooks.post_start`
- `hooks.reset`

### Multi-Agent

- `multi_agent`

## Nested Environment Types

### `resources`

- `cpu`
- `mem_gb`
- `gpu`
- `net`

### `mounts[]`

- `source`
- `target`
- `mode`: `ro` or `rw`

### `observation[]`

Supported observation types in the dataclass:

- `rgb_screen`
- `ui_tree`
- `audio_waveform`
- `cli_stdout`

Recognized observation fields:

- `type`
- `fps`
- `resolution`
- `sample_rate`
- `channels`
- `inline`
- `chunk_duration_ms`

### `action[]`

Supported action types in the dataclass:

- `mouse`
- `keyboard`
- `voice`
- `api_call`

Recognized action fields:

- `type`
- `events`
- `encoding`

### `recording`

- `enable`
- `output_dir`
- `video_fps`
- `video_resolution`
- `video_codec`
- `video_crf`
- `audio_rate`
- `audio_channels`
- `audio_codec`
- `force_audio_track`

### `vnc`

- `enable`
- `host_port`
- `container_port`
- `password`
- `view_only`
- `fallback_only`
- `note`

### `ssh`

- `user`
- `password`
- `key_file`
- `port`
- `shell`
- `note`

### `adb`

- `host_port`
- `guest_port`
- `timeout`
- `note`

### `avd`

- `api_level`
- `variant`
- `arch`
- `device`

### `apptainer`

- `sif`
- `definition`
- `image`
- `cache_dir`
- `binds`
- `overlays`
- `fakeroot`
- `contain`
- `contain_all`
- `writable_tmpfs`
- `enable_gpu`
- `env`
- `workdir`
- `extra_start_args`
- `extra_exec_args`

### `security`

- `user`
- `cap_drop`
- `cap_add`
- `devices`
- `seccomp_profile`
- `network_allowlist`
- `secrets_ref`
- `privileged`
- `use_systemd`
- `mount_cgroups`
- `cgroupns_host`
- `tmpfs_run`
- `stop_timeout`
- `runtime`

### `user_accounts[]`

Recognized user fields:

- `name`
- `password`
- `uid`
- `gid`
- `role`
- `permissions`

Recognized permissions fields:

- `sudo`
- `sudo_nopasswd`
- `shell`
- `groups`
- `primary_group`
- `home_dir`
- `home_permissions`
- `create_home`
- `login_shell`
- `system_user`
- `network_access`
- `max_processes`
- `max_memory`
- `env_vars`

## Task Spec

`TaskSpec` is loaded from `tasks/<task_id>/task.json` or `task.yaml`.

### Runtime-Recognized Top-Level Fields

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

### Extra Task Keys

Any top-level task keys that are not modeled explicitly are preserved in `TaskSpec.extras`.

## Nested Task Types

### `init`

- `init_script`
- `init_pyautogui`
- `timeout_sec`
- `max_steps`
- `reward_type`
- `reward_shaping`

`reward_type` supports these enum values:

- `sparse`
- `dense`
- `partial`
- `rubric`
- `continuous`

All of these reward types now map to runtime behavior, but they have different semantics:

- `sparse`: final pass/fail reward
- `dense`: per-step reward shaping function
- `partial` and `rubric`: final verifier score on `0-100`
- `continuous`: final verifier score normalized to `0.0-1.0`

### `hooks`

- `pre_task`
- `post_task`
- `pre_task_timeout`

### `success`

- `mode`
- `spec`

`mode` accepts:

- `program`
- `image_match`
- `multi`

These are the verifier modes currently supported by the runtime and validation path.

## Preset Merge Rules

If an environment declares `base`, the preset is loaded first and merged with the env file.

Current merge behavior:

- dicts are merged recursively
- `observation` lists merge by `type`
- `action` lists merge by `type`
- other lists are replaced by the override value

## Minimal Examples

### Environment

```json
{
  "id": "example.zotero_like@0.1",
  "base": "ubuntu-gnome-systemd_highres",
  "resources": {"cpu": 4, "mem_gb": 4, "net": true},
  "observation": [
    {"type": "rgb_screen", "fps": 10, "resolution": [1920, 1080]}
  ],
  "action": [
    {"type": "mouse"},
    {"type": "keyboard"}
  ],
  "mounts": [
    {"source": "benchmarks/environments/my_env/scripts", "target": "/workspace/scripts", "mode": "ro"},
    {"source": "benchmarks/environments/my_env/tasks", "target": "/workspace/tasks", "mode": "ro"}
  ],
  "hooks": {
    "pre_start": "/workspace/scripts/install.sh",
    "post_start": "/workspace/scripts/setup.sh"
  }
}
```

### Task

```json
{
  "id": "create_saved_search@1",
  "env_id": "zotero_env@0.1",
  "difficulty": "easy",
  "init": {
    "timeout_sec": 300,
    "max_steps": 40,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/create_saved_search/setup_task.sh",
    "post_task": "/workspace/tasks/create_saved_search/export_result.sh"
  },
  "metadata": {
    "search_name": "Papers Since 2010"
  },
  "success": {
    "mode": "program",
    "spec": {
      "program": "verifier.py::verify_create_saved_search"
    }
  }
}
```
