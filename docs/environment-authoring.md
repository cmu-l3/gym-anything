# Environment Authoring

This page documents the authoring pattern that matches the current runtime.

## Canonical Directory Layout

```text
benchmarks/cua_world/environments/<env_name>/
├── env.json
├── scripts/
├── tasks/
│   └── <task_id>/
│       ├── task.json
│       ├── verifier.py
│       ├── setup_task.sh          optional
│       ├── export_result.sh       optional
│       └── metadata/              optional
├── assets/                        optional
├── config/                        optional
├── data/                          optional large staged datasets
├── addons/                        optional app/plugin bundles
├── utils/                         optional
├── docs/                          environment-local documentation
├── dev/                           environment-local dev harnesses
├── metadata/                      curation and audit docs
├── evidence/                      screenshots and validation artifacts
└── artifacts/                     optional retained run outputs
```

Keep runtime files separate from curation material:

- runtime files belong in `env.json`, `scripts/`, `tasks/`, `assets/`, `config/`, `utils/`, `data/`, and `addons/`
- audit notes and validation writeups belong in `metadata/` or `evidence/`
- environment-local guides and troubleshooting snippets belong in `docs/`
- ad hoc validation harnesses belong in `dev/`, not beside runtime files

## Authoring Model

Each environment has:

- an environment spec
- zero or more shared install/setup scripts
- many task directories

Each task typically has:

- a task spec
- optional task setup hook
- optional task export hook
- a host-side verifier

## Environment Spec Pattern

Typical fields:

```json
{
  "id": "zotero_env@0.1",
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
    {"source": "benchmarks/cua_world/environments/zotero_env/scripts", "target": "/workspace/scripts", "mode": "ro"},
    {"source": "benchmarks/cua_world/environments/zotero_env/tasks", "target": "/workspace/tasks", "mode": "ro"}
  ],
  "hooks": {
    "pre_start": "/workspace/scripts/install_zotero.sh",
    "post_start": "/workspace/scripts/setup_zotero.sh"
  }
}
```

## Task Spec Pattern

Typical fields:

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

## Hook Semantics

Current order during `reset()`:

1. `env.hooks.pre_start`
2. `env.hooks.post_start`
3. `env.reset_script` or `env.hooks.reset`
4. `task.hooks.pre_task`
5. `task.init.init_script`
6. `task.init.init_pyautogui` for Windows flows

Current order during finalization:

1. `task.hooks.post_task`
2. verifier

## Recommended Pattern

### `pre_start`

Use for:

- package installation
- service installation
- one-time large setup work

### `post_start`

Use for:

- application bootstrapping
- seeding databases
- configuring defaults

### `pre_task`

Use for:

- task-specific state reset
- loading assets
- placing the app on the exact screen you want the agent to start from

### `post_task`

Use for:

- exporting structured evidence for the verifier
- copying state into a simple JSON or text format

## Verification Pattern

Best current pattern:

1. export task result into a simple file inside the environment
2. pull it in the verifier with `copy_from_env`
3. evaluate against `task.json -> metadata`

This is more robust than encoding large amounts of UI logic directly in the verifier.

## Practical Authoring Advice

- Make the start state deterministic. Close stale apps, relaunch cleanly, and land on the exact intended screen.
- Verify real display resolution inside the guest before relying on image-based coordinates.
- Prefer explicit readiness checks over fixed sleeps when bootstrapping apps or services.
- Keep environment-level and task-level responsibilities separate.
- If you need a field at runtime, add it to the dataclass and consuming code. Do not rely on ignored JSON keys.
- Put human audit material in `metadata/` and `evidence/`, not beside runtime files.
- Put local troubleshooting snippets in `docs/` and keep benchmark-facing runtime code out of `dev/`.

## Before You Contribute A New Environment

Check:

- the env loads through `from_config()`
- `verify spec` passes
- `reset()` works on the intended runner
- task setup is deterministic
- `step([], mark_done=True)` produces a verifier report
- docs mention any runner-specific requirements
