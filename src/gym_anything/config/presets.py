"""Canonical preset helpers.

The preset assets remain under ``gym_anything.presets`` because the JSON
definitions reference adjacent Dockerfiles and setup assets by path.
"""

from ..presets import (
    ALL_PRESETS,
    ANDROID_AVD_PRESETS,
    ANDROID_BLISSOS_PRESETS,
    ANDROID_PRESETS,
    APPTAINER_PRESETS,
    LINUX_PRESETS,
    WINDOWS_PRESETS,
    get_os_type,
    get_runner_type,
    is_android_env,
    is_android_preset,
    is_apptainer_env,
    is_apptainer_preset,
    is_avd_env,
    is_avd_preset,
    is_windows_env,
    is_windows_preset,
    list_presets,
    load_preset_env_dict,
)

__all__ = [
    "ALL_PRESETS",
    "ANDROID_AVD_PRESETS",
    "ANDROID_BLISSOS_PRESETS",
    "ANDROID_PRESETS",
    "APPTAINER_PRESETS",
    "LINUX_PRESETS",
    "WINDOWS_PRESETS",
    "get_os_type",
    "get_runner_type",
    "is_android_env",
    "is_android_preset",
    "is_apptainer_env",
    "is_apptainer_preset",
    "is_avd_env",
    "is_avd_preset",
    "is_windows_env",
    "is_windows_preset",
    "list_presets",
    "load_preset_env_dict",
]
