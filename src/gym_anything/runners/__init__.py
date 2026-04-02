"""Compatibility package for ``gym_anything.runners.*`` imports."""

from importlib import import_module
import sys

from ..runtime.runners import *  # noqa: F401,F403
from ..runtime.runners import __all__  # noqa: F401

_RUNNER_MODULES = (
    "apptainer_direct",
    "avd_apptainer",
    "avd_native",
    "avf",
    "avd_sdk_manager",
    "base",
    "build_android_qcow2_apptainer",
    "build_base_qcow2",
    "build_base_qcow2_nodocker",
    "build_windows_qcow2",
    "build_windows_qcow2_apptainer",
    "docker",
    "local",
    "qemu_apptainer",
    "qemu_native",
    "vnc_utils",
    "windows_pyautogui_client",
)

for _name in _RUNNER_MODULES:
    sys.modules[f"{__name__}.{_name}"] = import_module(f"gym_anything.runtime.runners.{_name}")
