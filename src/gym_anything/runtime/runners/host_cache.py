"""Shared host-cache layout for the bundled VM-family runners.

Party-side code (not core orchestration): runner classes compose their
`cache_components()` rows from these helpers, and the cache CLI only ever
iterates runner classes. Components are keyed by name and deduplicated by
the CLI, so families that share a store (qemu / qemu_native / avf) can all
declare it.
"""

from __future__ import annotations

from pathlib import Path
from typing import Dict, List

CACHE_ROOT = Path.home() / ".cache" / "gym-anything"

# Base files/dirs inside qemu/ that are expensive to rebuild.
# Anything else in qemu/ (and qemu/avf/) is treated as work.
QEMU_BASE_NAMES = {
    "base_ubuntu_gnome_arm64.qcow2",
    "base_ubuntu_gnome_arm64.raw",
    "base_ubuntu_gnome.qcow2",
    "ubuntu-cloud-arm64.img",
    "ubuntu-cloud.img",
}


def _qemu_work_paths() -> List[Path]:
    qemu = CACHE_ROOT / "qemu"
    if not qemu.exists():
        return []
    paths: List[Path] = []
    for entry in qemu.iterdir():
        if entry.name in QEMU_BASE_NAMES:
            continue
        if entry.name == "avf":
            for sub in entry.iterdir():
                if sub.name not in QEMU_BASE_NAMES:
                    paths.append(sub)
            continue
        paths.append(entry)
    return paths


def _qemu_base_paths() -> List[Path]:
    qemu = CACHE_ROOT / "qemu"
    if not qemu.exists():
        return []
    return [p for p in qemu.rglob("*") if p.name in QEMU_BASE_NAMES and p.is_file()]


def qemu_components() -> List[Dict]:
    return [
        {"name": "qemu-work", "category": "work", "paths": _qemu_work_paths(),
         "desc": "QEMU/AVF work directories and COW overlays (per-run state)"},
        {"name": "qemu-base", "category": "base", "paths": _qemu_base_paths(),
         "desc": "QEMU/AVF base VM images (~5 min to rebuild)"},
    ]


def apptainer_components() -> List[Dict]:
    return [
        {"name": "apptainer", "category": "work", "paths": [CACHE_ROOT / "apptainer"],
         "desc": "Apptainer SIF images and overlays"},
    ]


def avd_components() -> List[Dict]:
    return [
        {"name": "avd-checkpoints", "category": "work", "paths": [CACHE_ROOT / "avd-checkpoints"],
         "desc": "AVD checkpoint snapshots"},
        {"name": "android-sdk", "category": "base", "paths": [CACHE_ROOT / "android-sdk"],
         "desc": "Android SDK (requires network to re-download)"},
        {"name": "apks", "category": "base", "paths": [CACHE_ROOT / "apks"],
         "desc": "Downloaded Android APKs"},
        {"name": "avd", "category": "base", "paths": [CACHE_ROOT / "avd"],
         "desc": "Android Virtual Device definitions"},
    ]


def container_components() -> List[Dict]:
    return [
        {"name": "containers", "category": "work", "paths": [CACHE_ROOT / "containers"],
         "desc": "Container runtime cache"},
    ]
