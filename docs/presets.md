# Presets

Presets are built-in environment dictionaries loaded before an environment spec is converted into `EnvSpec`.

They live under `src/gym_anything/presets/`.

## Available Presets

Current preset groups from `src/gym_anything/presets/__init__.py`:

### Linux

- `x11-lite`
- `ubuntu-gnome`
- `ubuntu-gnome-systemd`
- `ubuntu-gnome-systemd_highres`
- `ubuntu-gnome-systemd_highres_gimp`
- `browser-chrome`
- `apptainer-xfce-gpu`

### Windows

- `windows-11`

### Android

- `android-14`
- `android-avd-35`
- `android-avd-34`

## How Presets Are Applied

When an env file contains:

```json
{
  "base": "ubuntu-gnome-systemd"
}
```

the loader:

1. loads the preset JSON
2. deep-merges the environment file on top of it
3. constructs `EnvSpec`

## Merge Rules

Current merge behavior:

- dicts merge recursively
- `observation` entries merge by `type`
- `action` entries merge by `type`
- other fields override directly

## Practical Notes By Preset Family

### `x11-lite`

Lightweight X11 + fluxbox preset for simple desktop tasks and smoke-style Linux GUI environments.

### `ubuntu-gnome`

Headless GNOME-style preset without the heavier systemd container requirements.

### `ubuntu-gnome-systemd`

Heavier Linux desktop preset using systemd-oriented container behavior. Usually the most realistic Linux desktop path in the Docker backend, but also the most sensitive to host/container setup.

### `browser-chrome`

Chromium-oriented Docker preset that exposes `api_call` in the action spec.

### `windows-11`

Windows preset intended for the QEMU/Apptainer path.

### `android-avd-*`

Official Android emulator presets that force the AVD runner through `runner: "avd"`.

### `apptainer-xfce-gpu`

Direct Apptainer preset for GPU-oriented Linux desktop use.

## Recommendation

Start from a preset whenever possible. It reduces boilerplate and ensures you inherit the runner-relevant defaults that the rest of the code expects.
