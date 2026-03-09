# Security

Security behavior is runner-dependent. The spec model exposes a broad set of fields, but not every field is enforced end-to-end on every runner.

## Isolation Layers

Current backend isolation options:

- QEMU VM inside Apptainer
- Docker container
- direct Apptainer container
- local no-op runner

In practice, QEMU provides the strongest guest isolation, while Docker and direct Apptainer provide container-level isolation.

## Security Fields In The Spec

`SecuritySpec` currently defines:

- `user`
- `cap_drop`
- `cap_add`
- `devices`
- `seccomp_profile`
- `secrets_ref`
- `privileged`
- `use_systemd`
- `mount_cgroups`
- `cgroupns_host`
- `tmpfs_run`
- `stop_timeout`
- `runtime`

## Important Implementation Notes

- `secrets_ref` loads host-side env, JSON, or YAML secret bundles into runner execution environments.
- `user_accounts` support is runner-dependent. The supported contract is documented in [Compatibility Checklist](compatibility.md).
- network defaults are not globally fixed; they come from presets and environment specs.

## Hook Privileges

Hook execution is not identical across all runners.

Current practical behavior:

- Docker hooks run through `docker exec`, effectively as root unless another user is specified
- Linux QEMU hooks are wrapped with `sudo -E`
- Windows hooks run through the Windows command path
- Android hooks run through ADB shell commands

Write hooks for the runner you actually plan to use.

## Systemd And Privileged Containers

Some Linux presets use systemd-style container setups. These often require:

- `privileged: true`
- cgroup-related flags
- a Linux host for the most reliable behavior

Docker Desktop can work inconsistently for systemd-heavy environments.

## Network

`resources.net` is the main runtime toggle used by current runners.

Typical use:

- `false` for offline tasks
- `true` for web apps, installers, remote access, or online services

Do not assume VNC or app networking will work if the environment is configured as offline.

## Credentials And Secrets

This repository contains many benchmark tasks with built-in demo credentials because the applications themselves are part of the benchmark setup.

That is different from operational secrets.

For operational credentials:

- do not hardcode them into hook scripts
- prefer `security.secrets_ref`, environment variables, or mounted files
- if you use Docker-in-Docker pulls, the current env loop will attempt guest-side DockerHub login from host env vars `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`

## Recommendation

For reproducible research:

- state which runner you used
- state whether networking was enabled
- state whether you used systemd or privileged containers
- do not assume a spec field is enforced just because it appears in the dataclass
