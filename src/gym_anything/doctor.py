from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import warnings
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

from .verification.imports import find_missing_imports


DEFAULT_KVM_DEVICE = "/dev/kvm"

def _probe_kvm_openable(device: str = DEFAULT_KVM_DEVICE) -> Tuple[bool, Optional[str]]:
    """Return (ok, reason) for whether the current process can open ``device`` RW.

    Used by ``get_runner_status`` to mark KVM-dependent runners as unavailable
    when the device is missing or not accessible. Returns the same reasons as
    :func:`check_kvm_access` so callers can surface actionable hints.
    """
    path = Path(device)

    if not path.exists():
        return False, f"{device} does not exist"

    try:
        mode = path.stat().st_mode
    except OSError as exc:
        return False, f"cannot stat {device}: {exc}"

    if not stat.S_ISCHR(mode):
        return False, f"{device} is not a character device"

    fd: Optional[int] = None
    try:
        fd = os.open(device, os.O_RDWR | getattr(os, "O_CLOEXEC", 0))
    except PermissionError:
        return False, f"{device} is not readable/writable by this process"
    except OSError as exc:
        return False, f"cannot open {device} read/write: {exc}"
    finally:
        if fd is not None:
            os.close(fd)

    return True, None


def check_kvm_access(device: str = DEFAULT_KVM_DEVICE) -> None:
    """Raise ``RuntimeError`` if ``device`` is not openable read/write.

    Wraps :func:`_probe_kvm_openable` for callers that want fail-fast behavior
    (e.g. the remote worker preflight). The message matches the probe reason.
    """
    ok, reason = _probe_kvm_openable(device)
    if not ok:
        raise RuntimeError(reason or f"{device} is not openable")


@dataclass(frozen=True)
class DoctorCheck:
    name: str
    ok: bool
    detail: str
    required: bool = True

    def to_dict(self) -> Dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class DoctorReport:
    checks: List[DoctorCheck] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return all(check.ok or not check.required for check in self.checks)

    def to_dict(self) -> Dict[str, object]:
        return {
            "ok": self.ok,
            "checks": [check.to_dict() for check in self.checks],
        }


def _command_available(command: str) -> Optional[str]:
    return shutil.which(command)


def _run_command(command: List[str], *, timeout: int = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout)


def _check_binary(
    name: str,
    binary: str,
    *,
    probe: Optional[List[str]] = None,
    required: bool = True,
    probe_timeout: int = 10,
) -> DoctorCheck:
    resolved = _command_available(binary)
    if not resolved:
        return DoctorCheck(name=name, ok=False, detail=f"{binary} not found on PATH", required=required)
    if probe is None:
        return DoctorCheck(name=name, ok=True, detail=f"{binary} -> {resolved}", required=required)
    try:
        result = _run_command(probe, timeout=probe_timeout)
    except Exception as exc:
        return DoctorCheck(name=name, ok=False, detail=f"{binary} probe failed: {exc}", required=required)
    if result.returncode == 0:
        return DoctorCheck(name=name, ok=True, detail=f"{binary} -> {resolved}", required=required)
    stderr = (result.stderr or result.stdout or "").strip()
    return DoctorCheck(
        name=name,
        ok=False,
        detail=f"{binary} present but probe failed: {stderr or 'non-zero exit'}",
        required=required,
    )


def _collect_runner_checks(runner: Optional[str]) -> List[DoctorCheck]:
    """Derive doctor checks from each runner's own status (laws L1/L4).

    With a specific runner: its dependency rows become required checks plus
    a required summary. With no runner: every runner's rows are diagnostic
    (WARN) and the overall verdict is a single runner_availability check —
    the host is OK as long as at least one runner is READY.
    """
    if runner is not None:
        statuses = {runner: _status_for_key(runner)}
        required = True
    else:
        statuses = get_runner_status()
        required = False

    checks: List[DoctorCheck] = []
    for key, status in statuses.items():
        for dep, row in (status.get("deps") or {}).items():
            detail = (
                row.get("path")
                or row.get("reason")
                or row.get("desc")
                or ("installed" if row.get("installed") else "missing")
            )
            if not row.get("installed") and row.get("install"):
                detail = f"{detail} — install: {row['install']}"
            checks.append(DoctorCheck(
                name=dep, ok=bool(row.get("installed")), detail=str(detail), required=required,
            ))
        summary = status.get("reason") or ("READY" if status.get("available") else "missing dependencies")
        checks.append(DoctorCheck(
            name=f"{key}_runner", ok=bool(status.get("available")), detail=str(summary), required=required,
        ))

    if runner is None:
        any_ready = any(s.get("available") for s in statuses.values())
        checks.append(DoctorCheck(
            name="runner_availability",
            ok=any_ready,
            detail=(
                "at least one runner is READY"
                if any_ready
                else "no runner is READY — see Runner Status for missing deps"
            ),
            required=True,
        ))
    return checks


def scan_verifier_imports(root: Path) -> DoctorCheck:
    missing_count = 0
    missing_modules: Dict[str, int] = {}
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", SyntaxWarning)
        for verifier_path in root.glob("*/tasks/*/verifier.py"):
            missing = find_missing_imports(
                verifier_path,
                task_root=verifier_path.parent,
                env_root=verifier_path.parents[2],
            )
            if not missing:
                continue
            missing_count += 1
            for module_name in missing:
                missing_modules[module_name] = missing_modules.get(module_name, 0) + 1
    if missing_count == 0:
        return DoctorCheck(
            name="verifier_imports",
            ok=True,
            detail=f"static verifier import scan passed under {root}",
        )
    summary = ", ".join(
        f"{name} ({count})" for name, count in sorted(missing_modules.items(), key=lambda item: (-item[1], item[0]))[:10]
    )
    return DoctorCheck(
        name="verifier_imports",
        ok=False,
        detail=f"{missing_count} verifier files reference missing modules: {summary}",
    )


def run_doctor(
    *,
    runner: Optional[str] = None,
    verification_root: Optional[Path] = None,
) -> DoctorReport:
    checks = _collect_runner_checks(runner)
    if verification_root is not None:
        checks.append(scan_verifier_imports(Path(verification_root)))
    return DoctorReport(checks=checks)


def render_doctor_text(report: DoctorReport) -> str:
    lines: List[str] = [f"overall={'ok' if report.ok else 'failed'}"]
    for check in report.checks:
        status = "ok" if check.ok else ("warn" if not check.required else "fail")
        lines.append(f"{status}: {check.name} - {check.detail}")
    return "\n".join(lines)


# --- Platform-aware install hints ---

import platform as _platform
import sys as _sys

_IS_MACOS = _sys.platform == "darwin"
_IS_LINUX = _sys.platform == "linux"
_IS_ARM = _platform.machine() in ("arm64", "aarch64")

# Maps binary name -> (description, install command per platform)
_INSTALL_HINTS: Dict[str, Dict[str, str]] = {
    "docker": {
        "desc": "Container runtime",
        "macos": "brew install --cask docker  # then open Docker.app",
        "linux": "curl -fsSL https://get.docker.com | sh",
    },
    "qemu-system-x86_64": {
        "desc": "x86_64 VM emulator",
        "macos": "brew install qemu",
        "linux": "sudo apt install qemu-system-x86",
    },
    "qemu-system-aarch64": {
        "desc": "ARM64 VM emulator (used on Apple Silicon)",
        "macos": "brew install qemu",
        "linux": "sudo apt install qemu-system-arm",
    },
    "qemu-img": {
        "desc": "QEMU disk image tool",
        "macos": "brew install qemu",
        "linux": "sudo apt install qemu-utils",
    },
    "mkisofs": {
        "desc": "ISO creation tool (for cloud-init)",
        "macos": "brew install cdrtools",
        "linux": "sudo apt install genisoimage",
    },
    "apptainer": {
        "desc": "Container runtime for HPC/SLURM",
        "macos": "N/A (Linux only)",
        "linux": "See https://apptainer.org/docs/admin/main/installation.html",
    },
    "vfkit": {
        "desc": "Apple Virtualization Framework CLI (macOS only)",
        "macos": "brew install vfkit",
        "linux": "N/A (macOS only)",
    },
    "gvproxy": {
        "desc": "Virtual network daemon for VM isolation",
        "macos": "curl -L -o /usr/local/bin/gvproxy https://github.com/containers/gvisor-tap-vsock/releases/latest/download/gvproxy-darwin && chmod +x /usr/local/bin/gvproxy",
        "linux": "curl -L -o /usr/local/bin/gvproxy https://github.com/containers/gvisor-tap-vsock/releases/latest/download/gvproxy-linux && chmod +x /usr/local/bin/gvproxy",
    },
    "ffmpeg": {
        "desc": "Screenshot and video capture",
        "macos": "brew install ffmpeg",
        "linux": "sudo apt install ffmpeg",
    },
    "adb": {
        "desc": "Android Debug Bridge",
        "macos": "brew install android-platform-tools",
        "linux": "sudo apt install adb",
    },
}

def _docker_daemon_alive() -> bool:
    """Return True if docker CLI is on PATH and the daemon responds quickly."""
    docker_bin = shutil.which("docker")
    if docker_bin is None:
        return False
    try:
        result = subprocess.run(
            [docker_bin, "info", "--format", "{{.ServerVersion}}"],
            capture_output=True,
            timeout=2,
        )
    except Exception:
        return False
    return result.returncode == 0


def binary_dep_row(binary: str, installed: Optional[bool] = None) -> Dict:
    """A dependency-status row for a host binary, with install hints.

    Shared helper for runner classes composing their own doctor_status —
    the hints catalog is keyed by binary, not by runner, so it stays here.
    """
    path = shutil.which(binary)
    if installed is None:
        installed = path is not None
    return {
        "installed": bool(installed),
        "path": path,
        "desc": _INSTALL_HINTS.get(binary, {}).get("desc", ""),
        "install": _INSTALL_HINTS.get(binary, {}).get("macos" if _IS_MACOS else "linux", ""),
    }


def kvm_dep_row(device: str = DEFAULT_KVM_DEVICE) -> Dict:
    """A dependency-status row for /dev/kvm access (Linux acceleration)."""
    kvm_ok, kvm_reason = _probe_kvm_openable(device)
    return {
        "installed": kvm_ok,
        "path": device if kvm_ok else None,
        "desc": "/dev/kvm openable read/write (hardware virtualization)",
        "install": (
            "sudo usermod -a -G kvm $USER  # then log out and back in"
            if kvm_reason and "readable/writable" in kvm_reason
            else "ensure /dev/kvm exists and the worker process can open it RW"
        ),
        "reason": kvm_reason,
    }


def _status_for_key(key: str) -> Dict:
    """Resolve one runner key and query the class for its own status."""
    from .runtime.runners import registry as runner_registry

    conflicts = runner_registry.registry_conflicts()
    if key in conflicts:
        return {"available": False, "reason": conflicts[key], "deps": {}}
    try:
        cls = runner_registry.resolve_runner_class(key)
    except Exception as exc:
        return {"available": False, "reason": str(exc), "deps": {}}
    if cls is None:
        return {"available": False, "reason": f"unknown runner {key!r}", "deps": {}}
    try:
        return dict(cls.doctor_status())
    except Exception as exc:
        return {"available": False, "reason": f"doctor_status failed: {exc}", "deps": {}}


def get_runner_status() -> Dict[str, Dict]:
    """Status of every registered runner, each reported by its own class.

    Family keys report the class dispatch would actually use on this host
    (e.g. `qemu` on macOS reports the native-QEMU path), so doctor, worker
    advertising, and env dispatch can never disagree.
    """
    from .runtime.runners import registry as runner_registry

    results: Dict[str, Dict] = {}
    for key in runner_registry.list_runner_keys():
        results[key] = _status_for_key(key)
    for key, reason in runner_registry.registry_conflicts().items():
        results[key] = {"available": False, "reason": reason, "deps": {}}
    return results


def get_available_runners(runner_status: Optional[Dict[str, Dict]] = None) -> List[str]:
    """Return the keys of runners whose deps are fully satisfied on this host."""
    statuses = runner_status if runner_status is not None else get_runner_status()
    return [
        runner
        for runner, status in statuses.items()
        if status.get("available")
    ]


def get_recommended_runner(runner_status: Optional[Dict[str, Dict]] = None) -> Optional[str]:
    """Pick the recommended runner for this platform.

    Preference is a per-party fact: each runner class declares its platform
    fitness (platform_priority) and core sorts. Returns the top-priority
    runner regardless of whether its deps are installed — doctor offers to
    install it when missing, which keeps the recommendation stable.
    """
    del runner_status  # kept for signature compatibility; priority is class-declared
    from .runtime.runners import registry as runner_registry

    best_key: Optional[str] = None
    best_priority = 0
    for key in runner_registry.list_runner_keys():
        try:
            cls = runner_registry.resolve_runner_class(key)
        except Exception:
            continue
        if cls is None:
            continue
        try:
            priority = int(cls.platform_priority())
        except Exception:
            continue
        if priority < 10:  # synthetic/fallback runners are never a recommendation
            continue
        if priority > best_priority or (priority == best_priority and best_key is not None and key < best_key):
            best_key, best_priority = key, priority
    return best_key


def render_doctor_rich(report: DoctorReport) -> str:
    """Render a user-friendly doctor output with runner status and install hints."""
    lines: List[str] = []

    # Platform info
    lines.append(f"Platform: {_sys.platform} ({_platform.machine()})")
    lines.append("")

    # Runner status
    runner_status = get_runner_status()

    recommended = get_recommended_runner(runner_status)

    lines.append("Runners:")
    lines.append("")

    for runner_key, status in runner_status.items():
        reason = status.get("reason")
        if reason:
            lines.append(f"  {runner_key}: -- ({reason})")
            continue

        available = status["available"]
        tag = "READY" if available else "MISSING DEPS"
        rec = " (recommended)" if runner_key == recommended else ""
        lines.append(f"  {runner_key}: {tag}{rec}")

        for dep, info in status["deps"].items():
            if info["installed"]:
                lines.append(f"    [ok] {dep} -> {info['path']}")
            else:
                lines.append(f"    [!!] {dep} -- not installed")
                if info["install"]:
                    lines.append(f"         Install: {info['install']}")

    # Missing deps summary
    missing = []
    if recommended and not runner_status.get(recommended, {}).get("available"):
        for dep, info in runner_status[recommended]["deps"].items():
            if not info["installed"]:
                missing.append((dep, info["install"]))

    if missing:
        lines.append("")
        lines.append(f"To set up the recommended runner ({recommended}):")
        lines.append("")
        for dep, install_cmd in missing:
            if install_cmd:
                lines.append(f"  {install_cmd}")

    return "\n".join(lines)


__all__ = [
    "DEFAULT_KVM_DEVICE",
    "DoctorCheck",
    "DoctorReport",
    "check_kvm_access",
    "get_available_runners",
    "get_recommended_runner",
    "get_runner_status",
    "render_doctor_text",
    "run_doctor",
    "scan_verifier_imports",
]
