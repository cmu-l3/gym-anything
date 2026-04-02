"""
AVD Native Runner -- runs Android emulator directly without Apptainer.

Designed for macOS and bare-metal Linux where the Android emulator runs
natively. Uses the same env.json files as AVDApptainerRunner.

Acceleration:
    - Linux: KVM (/dev/kvm)
    - macOS: HVF (Hypervisor.framework, auto-detected by the emulator)
    - Fallback: software emulation (-accel off)

Usage:
    export GYM_ANYTHING_RUNNER=avd_native
    # or: export GYM_ANYTHING_RUNNER=avd  (auto-selects native if Apptainer unavailable)
"""

from __future__ import annotations

import os
import platform
import sys
from pathlib import Path
from typing import List, Optional

from ...specs import EnvSpec
from .avd_apptainer import AVDApptainerRunner


class AVDNativeRunner(AVDApptainerRunner):
    """AVD runner for macOS and bare-metal Linux (no Apptainer).

    On Apple Silicon, automatically switches to arm64-v8a system images
    for native HVF acceleration instead of emulating x86_64.
    """

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        # On Apple Silicon, override arch to arm64-v8a for native HVF speed
        if sys.platform == "darwin" and platform.machine() == "arm64":
            if self.arch == "x86_64":
                print("[AVDNative] Apple Silicon: switching to arm64-v8a system image for HVF")
                self.arch = "arm64-v8a"

    def _detect_acceleration(self) -> bool:
        """Detect hardware acceleration, including HVF on macOS.

        The Android emulator auto-selects HVF on macOS when -accel on is passed.
        Returns True if hardware acceleration is available.
        """
        if sys.platform == "linux":
            available = (
                os.path.exists("/dev/kvm")
                and os.access("/dev/kvm", os.R_OK | os.W_OK)
            )
            if not available:
                print("[AVDNative] WARNING: /dev/kvm not available, using software emulation (very slow)")
            return available
        elif sys.platform == "darwin":
            # The Android emulator on macOS auto-selects HVF when -accel on is passed.
            # On Intel Macs, HVF works for x86_64 guests.
            # On Apple Silicon, the emulator uses Rosetta + HVF for x86_64 system images,
            # or native HVF for arm64 system images.
            if platform.machine() in ("x86_64", "arm64"):
                return True
            print(f"[AVDNative] WARNING: Unknown architecture {platform.machine()}, acceleration may not work")
            return True  # Let the emulator figure it out
        else:
            print(f"[AVDNative] WARNING: Unsupported platform {sys.platform}")
            return False

    def _ensure_container(self) -> Optional[Path]:
        """No container needed -- emulator runs directly on host."""
        return None

    def _build_launch_cmd(self, startup_script: Path, container_sif: Optional[Path],
                          sdk_root: str, avd_home: str, android_home: str,
                          work_dir: str) -> List[str]:
        """Run the startup script directly (no Apptainer wrapping).

        The startup script sets environment variables and exec's the emulator,
        so running it via bash is sufficient.
        """
        return ["bash", str(startup_script)]
