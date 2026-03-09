# Runners

Runners are backend implementations of the runtime interface in `BaseRunner`.

For the release-facing capability contract, see [Compatibility Checklist](compatibility.md).

They are responsible for:

- starting and stopping environments
- injecting actions
- capturing screenshots and other observations
- running commands
- copying files
- optionally supporting checkpoint caching

## Selection Logic

The current selection logic lives in `GymAnythingEnv._select_runner()`.

Selection order:

1. `GYM_ANYTHING_RUNNER=avd` or `spec.runner == "avd"` -> `AVDApptainerRunner`
2. `GYM_ANYTHING_RUNNER=apptainer` or `spec.runner == "apptainer"` -> `ApptainerDirectRunner`
3. `GYM_ANYTHING_RUNNER=browser`, `spec.runner == "browser"`, or `spec.base == "browser-chrome"` -> `BrowserRunner`
4. `GYM_ANYTHING_RUNNER=qemu` -> `QemuApptainerRunner`
5. `GYM_ANYTHING_RUNNER=local` -> `LocalRunner`
6. `spec.runner == "qemu"` -> `QemuApptainerRunner`
7. if Docker is unavailable but Apptainer is available -> `QemuApptainerRunner`
8. if `spec.image` or `spec.dockerfile` is set -> `DockerRunner`
9. otherwise -> `LocalRunner`

Important implications:

- Docker is only chosen automatically when the resolved env spec has `image` or `dockerfile`.
- Presets matter because they often supply those fields.

## DockerRunner

Best current fit for Linux desktop and service environments on a single machine.

Implemented behavior:

- X11 display bootstrap unless `skip_display_audio_bootstrap` is set
- xdotool and PyAutoGUI-based Linux input injection
- per-step screenshot capture via FFmpeg `x11grab`
- optional audio capture for observations
- continuous FFmpeg recording in `GymAnythingEnv.reset()`
- Docker image commit-based checkpoints
- `user_accounts` setup logic is implemented here

Notes:

- this is the only runner that currently starts live `recording.mp4` capture during the episode
- hook scripts and verifier file movement are well supported here

## QemuApptainerRunner

Primary VM-style backend for HPC or cluster environments.

Implemented behavior:

- boots Linux, Windows, or Android-like guests under QEMU in Apptainer
- Linux command execution via SSH, Windows via SSH/PowerShell, Android via ADB
- screenshot capture via guest-native path with VNC fallback
- checkpoint files backed by QCOW2 images
- optional `savevm`/`loadvm` fast restore for QEMU only

Notes:

- Linux commands are wrapped with `sudo -E` to approximate Docker-root behavior
- live FFmpeg recording is not started by `GymAnythingEnv`, but step screenshots can still be assembled into `recording.mp4` on close when host `ffmpeg` is available
- Windows uses a PyAutoGUI TCP server for desktop input

## AVDApptainerRunner

Official Android emulator backend.

Implemented behavior:

- Android SDK and AVD management
- ADB-based input and command execution
- checkpoint directories containing emulator state
- APK installation support through env spec fields

Notes:

- screenshot capture works
- live FFmpeg episode recording is not started by the main env loop, but step-video assembly can still produce `recording.mp4`
- the runner supports checkpoint methods, unlike older docs that implied otherwise

## ApptainerDirectRunner

Direct container runner for GPU-enabled Linux desktop workflows.

Implemented behavior:

- direct Apptainer instances instead of full VMs
- VNC-based input preferred for apps that reject synthetic X11 input
- xdotool fallback
- screenshot capture and command execution inside the container

Notes:

- checkpoint methods exist but are currently placeholders rather than real caching
- this runner is promising for GPU-heavy apps, but less integrated than Docker and QEMU paths

## LocalRunner

Minimal smoke-test backend.

Implemented behavior:

- no real GUI
- no-op actions
- synthetic blank observations

Use it for:

- import smoke tests
- control-flow checks
- basic verifier development

Do not use it as evidence that a real environment works.

## Release-Facing Support Matrix

The canonical supported matrix now lives in [Compatibility Checklist](compatibility.md).

Use this page for runtime mechanics and selection behavior, and use the compatibility checklist when you need the public contract for research reproducibility or deployment planning.

## Runner-Specific Action Caveats

The low-level nested action format is mostly shared, but behavior still varies:

- `voice` is Docker-specific
- `api_call` is Docker-oriented and depends on environment support
- Android interprets some mouse actions as taps, long-presses, or swipes
- Windows input is routed through a PyAutoGUI server
- Direct Apptainer prefers VNC input for Qt-heavy apps

For research reproducibility, document which runner you used.
