from __future__ import annotations

import json
from importlib import resources
from typing import Dict, Any


# Available presets organized by category
LINUX_PRESETS = (
    "x11-lite",
    "ubuntu-gnome",
    "ubuntu-gnome-systemd",
    "ubuntu-gnome-systemd_highres",
    "ubuntu-gnome-systemd_highres_gimp",
    "apptainer-xfce-gpu",
)

# Apptainer-native presets (direct Apptainer, not QEMU-in-Apptainer)
APPTAINER_PRESETS = (
    "apptainer-xfce-gpu",
)

WINDOWS_PRESETS = (
    "windows-11",
)

# BlissOS-based Android (QEMU direct boot)
ANDROID_BLISSOS_PRESETS = (
    "android-14",
)

# AVD-based Android (official emulator)
ANDROID_AVD_PRESETS = (
    "android-avd-35",
    "android-avd-34",
)

ANDROID_PRESETS = ANDROID_BLISSOS_PRESETS + ANDROID_AVD_PRESETS

ALL_PRESETS = LINUX_PRESETS + WINDOWS_PRESETS + ANDROID_PRESETS


def load_preset_env_dict(name: str) -> Dict[str, Any]:
    """Load a built-in preset env dict by name.

    Linux presets: 'x11-lite', 'ubuntu-gnome', 'ubuntu-gnome-systemd', etc.
    Windows presets: 'windows-11'
    """
    pkg = __name__
    if name not in ALL_PRESETS:
        raise ValueError(f"Unknown preset: {name}. Available: {', '.join(ALL_PRESETS)}")
    fname = f"{name}.json"
    with resources.files(pkg).joinpath(fname).open("r", encoding="utf-8") as f:
        return json.load(f)


def is_windows_preset(name: str) -> bool:
    """Check if a preset is Windows-based."""
    return name in WINDOWS_PRESETS


def get_os_type(preset_dict: Dict[str, Any]) -> str:
    """Get OS type from preset dict ('linux' or 'windows')."""
    return preset_dict.get("os_type", "linux")


def is_windows_env(env_dict: Dict[str, Any]) -> bool:
    """Check if an environment dict is Windows-based.

    Checks the os_type field or the base preset name.
    """
    if env_dict.get("os_type") == "windows":
        return True
    base = env_dict.get("base", "")
    if base and is_windows_preset(base):
        return True
    return False


def is_android_preset(name: str) -> bool:
    """Check if a preset is Android-based."""
    return name in ANDROID_PRESETS


def is_android_env(env_dict: Dict[str, Any]) -> bool:
    """Check if an environment dict is Android-based.

    Checks the os_type field or the base preset name.
    """
    if env_dict.get("os_type") == "android":
        return True
    base = env_dict.get("base", "")
    if base and is_android_preset(base):
        return True
    return False


def is_avd_preset(name: str) -> bool:
    """Check if a preset uses AVD emulator (vs BlissOS/QEMU)."""
    return name in ANDROID_AVD_PRESETS


def is_avd_env(env_dict: Dict[str, Any]) -> bool:
    """Check if an environment dict uses AVD emulator.

    Checks the runner field or base preset name.
    """
    if env_dict.get("runner") == "avd":
        return True
    base = env_dict.get("base", "")
    if base and is_avd_preset(base):
        return True
    return False


def is_apptainer_preset(name: str) -> bool:
    """Check if a preset uses direct Apptainer runner (not QEMU-in-Apptainer)."""
    return name in APPTAINER_PRESETS


def is_apptainer_env(env_dict: Dict[str, Any]) -> bool:
    """Check if an environment dict uses direct Apptainer runner.

    Checks the runner field or base preset name.
    """
    if env_dict.get("runner") == "apptainer":
        return True
    base = env_dict.get("base", "")
    if base and is_apptainer_preset(base):
        return True
    return False


def get_runner_type(env_dict: Dict[str, Any]) -> str:
    """Determine the runner type for an environment.

    Returns:
        Runner type: 'docker', 'qemu', 'avd', 'apptainer', or 'local'
    """
    # Explicit runner specification
    if env_dict.get("runner"):
        return env_dict["runner"]

    # Direct Apptainer (GPU-enabled, no QEMU)
    if is_apptainer_env(env_dict):
        return "apptainer"

    # AVD-based Android
    if is_avd_env(env_dict):
        return "avd"

    # BlissOS/QEMU Android or Windows
    if is_android_env(env_dict) or is_windows_env(env_dict):
        return "qemu"

    # Default to qemu for Linux when using QEMU runner
    return "qemu"


def list_presets() -> Dict[str, tuple]:
    """List all available presets by category."""
    return {
        "linux": LINUX_PRESETS,
        "windows": WINDOWS_PRESETS,
        "android_blissos": ANDROID_BLISSOS_PRESETS,
        "android_avd": ANDROID_AVD_PRESETS,
        "android": ANDROID_PRESETS,
        "apptainer": APPTAINER_PRESETS,
    }
