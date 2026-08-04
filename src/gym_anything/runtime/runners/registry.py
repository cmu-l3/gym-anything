"""The runner door: one table mapping runner keys to selectors.

Law L1 (one door): built-in runners, pip-installed runners (entry points in
the ``gym_anything.runners`` group), and explicitly registered runners all
enter through this table, and every consumer of "which runners exist" (env
dispatch, spec validation, doctor, CLI) reads it. Core never keys control
flow on a specific runner name.

A *selector* resolves a key to the concrete ``BaseRunner`` subclass for this
host and spec. Family keys ("qemu", "avd") pick a class per platform — the
same decisions ``GymAnythingEnv`` historically made inline. Selectors return
classes, not instances, so doctor/CLI can ask a key for its class-level
facts without starting anything.

Locator references ("pkg.mod:ClassName") bypass the table entirely: any
importable ``BaseRunner`` subclass is a valid runner with zero registration
(L1: references are structural). Registration only buys a short name.

Collision semantics: built-in keys are reserved; two entry points claiming
the same key with different targets is an error surfaced when that key is
used (not at import, so one broken install cannot take down ``--help``);
``register_runner(..., replace=True)`` is the only override path. Install
order must never decide what a name means.
"""

from __future__ import annotations

import importlib
import logging
import platform
import shutil
import subprocess
import sys
from typing import Callable, Dict, List, Optional, Type

from .base import BaseRunner

logger = logging.getLogger(__name__)

ENTRY_POINT_GROUP = "gym_anything.runners"

# A selector maps (spec-or-None) to the runner class this host would use.
# ``spec`` is optional so class-level consumers (doctor, CLI listings) can
# resolve without an environment in hand.
Selector = Callable[[Optional[object]], Type[BaseRunner]]


class RunnerRegistryError(RuntimeError):
    """A runner key is unusable: conflicting registrations or bad locator."""


# --- host availability probes (moved verbatim from GymAnythingEnv) ---------

def docker_available() -> bool:
    """Check if Docker daemon is available and running."""
    try:
        result = subprocess.run(["docker", "info"], capture_output=True, timeout=5)
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def apptainer_available() -> bool:
    """Check if Apptainer is installed."""
    try:
        result = subprocess.run(["apptainer", "--version"], capture_output=True, timeout=5)
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def qemu_native_available() -> bool:
    """Check if QEMU is installed directly on the host."""
    if platform.machine() in ("arm64", "aarch64"):
        return shutil.which("qemu-system-aarch64") is not None
    return shutil.which("qemu-system-x86_64") is not None


def avf_available() -> bool:
    """Check if Apple Virtualization Framework tooling is available."""
    return shutil.which("vfkit") is not None and shutil.which("gvproxy") is not None


# --- built-in selectors ----------------------------------------------------

def _select_docker(spec=None) -> Type[BaseRunner]:
    from .docker import DockerRunner
    return DockerRunner


def _select_local(spec=None) -> Type[BaseRunner]:
    from .local import LocalRunner
    return LocalRunner


def _select_qemu(spec=None) -> Type[BaseRunner]:
    """Family key: QemuApptainer on Linux with apptainer, QemuNative otherwise."""
    from .qemu_native import QemuNativeRunner
    if sys.platform == "darwin":
        return QemuNativeRunner
    if apptainer_available():
        from .qemu_apptainer import QemuApptainerRunner
        return QemuApptainerRunner
    if qemu_native_available():
        return QemuNativeRunner
    raise RuntimeError(
        "runner=qemu but neither Apptainer nor native QEMU found. "
        "Install Apptainer or QEMU (brew install qemu / apt install qemu-system-x86)."
    )


def _select_qemu_native(spec=None) -> Type[BaseRunner]:
    from .qemu_native import QemuNativeRunner
    return QemuNativeRunner


def _select_avd(spec=None) -> Type[BaseRunner]:
    """Family key: AVDApptainer on Linux with apptainer, AVDNative otherwise."""
    from .avd_native import AVDNativeRunner
    if sys.platform == "darwin":
        return AVDNativeRunner
    if apptainer_available():
        from .avd_apptainer import AVDApptainerRunner
        return AVDApptainerRunner
    return AVDNativeRunner


def _select_avd_native(spec=None) -> Type[BaseRunner]:
    from .avd_native import AVDNativeRunner
    return AVDNativeRunner


def _select_avf(spec=None) -> Type[BaseRunner]:
    from .avf import AVFRunner
    return AVFRunner


def _select_apptainer(spec=None) -> Type[BaseRunner]:
    from .apptainer_direct import ApptainerDirectRunner
    return ApptainerDirectRunner


def _select_modal(spec=None) -> Type[BaseRunner]:
    from .modal_runner import ModalRunner
    return ModalRunner


def _select_modal_native(spec=None) -> Type[BaseRunner]:
    from .modal_native import ModalNativeRunner
    return ModalNativeRunner


def _select_use_computer(spec=None) -> Type[BaseRunner]:
    from .use_computer import UseComputerRunner
    return UseComputerRunner


_BUILTINS: Dict[str, Selector] = {
    "docker": _select_docker,
    "qemu": _select_qemu,
    "qemu_native": _select_qemu_native,
    "avd": _select_avd,
    "avd_native": _select_avd_native,
    "avf": _select_avf,
    "apptainer": _select_apptainer,
    "modal": _select_modal,
    "modal_native": _select_modal_native,
    "use_computer": _select_use_computer,
    "local": _select_local,
}

_table: Dict[str, Selector] = dict(_BUILTINS)
_conflicts: Dict[str, str] = {}
_entry_points_loaded = False


def _selector_from_entry_point(loaded) -> Selector:
    """An entry point may name a BaseRunner subclass or a selector callable."""
    if isinstance(loaded, type) and issubclass(loaded, BaseRunner):
        return lambda spec=None, _cls=loaded: _cls
    if callable(loaded):
        return loaded
    raise RunnerRegistryError(
        f"entry point value {loaded!r} is neither a BaseRunner subclass nor a selector callable"
    )


def _load_entry_points() -> None:
    global _entry_points_loaded
    if _entry_points_loaded:
        return
    _entry_points_loaded = True
    try:
        from importlib.metadata import entry_points
        eps = entry_points(group=ENTRY_POINT_GROUP)
    except Exception as exc:  # metadata backend failure must not break core
        logger.warning("Could not read %s entry points: %s", ENTRY_POINT_GROUP, exc)
        return
    seen: Dict[str, str] = {}
    for ep in eps:
        if ep.name in _BUILTINS:
            _conflicts[ep.name] = (
                f"entry point {ep.value!r} claims built-in runner key {ep.name!r}; built-in names are reserved"
            )
            continue
        if ep.name in seen:
            if seen[ep.name] == ep.value:
                continue  # identical duplicate (e.g. editable + stale wheel): harmless
            _conflicts[ep.name] = (
                f"conflicting entry points for runner key {ep.name!r}: "
                f"{seen[ep.name]!r} vs {ep.value!r}"
            )
            _table.pop(ep.name, None)
            continue
        seen[ep.name] = ep.value
        try:
            _table[ep.name] = _selector_from_entry_point(ep.load())
        except Exception as exc:
            _conflicts[ep.name] = f"entry point {ep.value!r} failed to load: {exc}"


def register_runner(key: str, selector, *, replace: bool = False) -> None:
    """Register a short runner name in code. The explicit override path."""
    _load_entry_points()
    resolved = _selector_from_entry_point(selector)
    if key in _table and not replace:
        kind = "built-in" if key in _BUILTINS else "registered"
        raise RunnerRegistryError(
            f"runner key {key!r} is already {kind}; pass replace=True to override explicitly"
        )
    _conflicts.pop(key, None)
    _table[key] = resolved


def registry_conflicts() -> Dict[str, str]:
    """Conflicting/broken registrations, for doctor to report."""
    _load_entry_points()
    return dict(_conflicts)


def list_runner_keys() -> List[str]:
    _load_entry_points()
    return sorted(_table)


def is_locator(ref: str) -> bool:
    return ":" in ref


def _resolve_locator(ref: str) -> Type[BaseRunner]:
    module_name, _, attr = ref.partition(":")
    try:
        module = importlib.import_module(module_name)
    except ImportError as exc:
        raise RunnerRegistryError(f"cannot import runner locator {ref!r}: {exc}") from exc
    try:
        cls = getattr(module, attr)
    except AttributeError as exc:
        raise RunnerRegistryError(f"runner locator {ref!r}: {module_name} has no attribute {attr!r}") from exc
    if not (isinstance(cls, type) and issubclass(cls, BaseRunner)):
        raise RunnerRegistryError(f"runner locator {ref!r} is not a BaseRunner subclass")
    return cls


def resolve_runner_class(ref: str, spec=None) -> Optional[Type[BaseRunner]]:
    """Resolve a runner reference to a class.

    - Locator ("pkg.mod:Class"): imported and type-checked; errors raise
      (a typo must not silently fall back to auto-detect).
    - Table key: selector applied; unknown keys return None so callers keep
      their historical warn-and-fall-back behavior.
    - Conflicted key: raises with the conflict reason (errors at first use).
    """
    if is_locator(ref):
        return _resolve_locator(ref)
    _load_entry_points()
    if ref in _conflicts:
        raise RunnerRegistryError(_conflicts[ref])
    selector = _table.get(ref)
    if selector is None:
        return None
    return selector(spec)


def is_known_reference(ref: str) -> bool:
    """True if ``ref`` names a usable runner (key or importable locator)."""
    if is_locator(ref):
        try:
            _resolve_locator(ref)
            return True
        except RunnerRegistryError:
            return False
    _load_entry_points()
    return ref in _table


def autodetect_runner_class(spec=None) -> Type[BaseRunner]:
    """Pick the best available runner class for this host.

    Preference is a per-party fact (law L1): each class declares its
    platform_priority and autodetect eligibility; core sorts, queries
    availability (law L4), and takes the best. LocalRunner (priority 1) is
    the universal synthetic fallback.
    """
    _load_entry_points()
    candidates = []
    seen = set()
    for key in sorted(_table):
        try:
            cls = _table[key](spec)
        except Exception:
            continue
        if cls in seen:
            continue
        seen.add(cls)
        try:
            priority = int(cls.platform_priority())
        except Exception:
            continue
        if priority > 1:
            candidates.append((priority, cls.__name__, cls))
    candidates.sort(key=lambda item: (-item[0], item[1]))
    for _, _, cls in candidates:
        try:
            if not cls.autodetect_eligible(spec):
                continue
            if not cls.doctor_status().get("available"):
                continue
        except Exception:
            continue
        logger.info("Using %s (auto-detected)", cls.__name__)
        return cls

    logger.warning("No suitable runtime found. Run: gym-anything doctor")
    from .local import LocalRunner
    return LocalRunner


__all__ = [
    "ENTRY_POINT_GROUP",
    "RunnerRegistryError",
    "autodetect_runner_class",
    "apptainer_available",
    "avf_available",
    "docker_available",
    "is_known_reference",
    "is_locator",
    "list_runner_keys",
    "qemu_native_available",
    "register_runner",
    "registry_conflicts",
    "resolve_runner_class",
]
