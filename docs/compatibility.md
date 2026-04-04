# Compatibility Checklist

This page defines the supported runner-by-runner contract for Gym-Anything.

These differences are not treated as bugs by themselves. They are part of the release-facing compatibility surface and should be used when choosing a runner for a workload.

## How To Use This Page

- If a capability is listed as supported here, it is part of the intended public contract.
- If a capability is missing here, do not rely on it as portable behavior across runners.
- If your benchmark or deployment depends on a capability that is runner-specific, state the runner explicitly in papers, configs, and reproductions.

You can inspect the same contract from the CLI:

```bash
PYTHONPATH=src python -m gym_anything.cli compatibility
PYTHONPATH=src python -m gym_anything.cli compatibility --runner qemu --json
```

You can also inspect the active runtime contract from Python:

```python
from gym_anything import from_config, get_runner_compatibility

print(get_runner_compatibility("docker").to_dict())

env = from_config("benchmarks/cua_world/environments/zotero_env", task_id="create_saved_search")
print(env.get_compatibility_profile())
env.close()
```

## Runner Matrix

| Capability | Docker | Browser | QEMU | AVD | Direct Apptainer | Local |
|---|---|---|---|---|---|---|
| Real application runtime | Yes | Yes | Yes | Android only | Yes | No |
| Live recording during episode | Yes | Yes | No | No | No | No |
| MP4 assembly from screenshots on close | Yes | Yes | Yes | Yes | Yes | No |
| Checkpoint caching | Yes | Yes | Yes | Yes | No | No |
| `use_savevm` | No | No | Yes | No | No | No |
| `user_accounts` from spec | Yes | Yes | Metadata/preprovisioned only | Metadata only | Metadata/preprovisioned only | No |
| Windows guest support | No | No | Yes | No | No | No |
| Android guest support | No | No | Partial | Yes | No | No |

## Runner Notes

### Docker

- `user_accounts` is provisioned from `EnvSpec.user_accounts`.
- This is the main Linux desktop and service runner.
- Continuous FFmpeg recording is started directly by `GymAnythingEnv.reset()`.

### Browser

- `BrowserRunner` inherits the Docker runtime path and adds browser-specific control APIs.
- It follows the same account-provisioning and recording contract as Docker.
- Use it when the environment is intentionally browser-scoped rather than a generic desktop container.

### QEMU

- `use_savevm` is only meaningful here.
- Checkpoint caching is supported.
- Guest accounts are generally prebuilt in the guest image; `user_accounts` should be treated as compatible metadata rather than portable guest-side provisioning logic.

### AVD

- This is the Android emulator runner.
- Checkpoint caching is supported.
- `user_accounts` is metadata only; it does not create Android users from the spec.

### Direct Apptainer

- This is a real Linux application runner, but it does not currently support checkpoint caching.
- `user_accounts` should be treated as credential/config metadata for preprovisioned images, not as portable provisioning behavior.
- Prefer this runner when direct containerized Linux desktop execution is required and checkpoint caching is not part of the workload contract.

### Local

- This is a smoke-test backend only.
- It provides synthetic observations and no real GUI runtime.
- Do not treat successful Local runs as evidence that a benchmark environment works.

## User Accounts Contract

`EnvSpec.user_accounts` is part of the public spec, but the supported behavior depends on the runner:

- `provision_from_spec`: the runner creates/configures accounts from the spec
- `preprovisioned_accounts`: the runner expects the image or VM to already contain the effective accounts
- `metadata_only`: the field is descriptive and may still be useful for credentials, roles, or external orchestration
- `unsupported`: do not rely on `user_accounts`

Current mapping:

- Docker: `provision_from_spec`
- Browser: `provision_from_spec`
- QEMU: `preprovisioned_accounts`
- AVD: `metadata_only`
- Direct Apptainer: `preprovisioned_accounts`
- Local: `unsupported`

## Recording Contract

- Docker and Browser provide live episode recording.
- QEMU, AVD, and Direct Apptainer provide screenshot-based trajectory capture and can assemble `recording.mp4` on close when host `ffmpeg` is available.
- Local does not provide real recording artifacts.

## Checkpoint Contract

- Docker, Browser, QEMU, and AVD support checkpoint caching.
- Only QEMU supports `use_savevm=True`.
- Direct Apptainer and Local do not support checkpoint caching.

## Release Policy

Changes to this page should track real code behavior and tests. New capabilities should only be added after they are implemented, documented, and covered by the release test surface.
