from __future__ import annotations

import shutil
import subprocess
import warnings
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional

from .verification.imports import find_missing_imports


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
    target = runner or "all"
    checks: List[DoctorCheck] = []
    if target in {"all", "docker"}:
        checks.append(_check_binary("docker_cli", "docker", probe=["docker", "--version"]))
        checks.append(_check_binary(
            "docker_daemon", "docker", probe=["docker", "info"], probe_timeout=3,
        ))
    if target in {"all", "qemu", "avd", "apptainer"}:
        # Apptainer is Linux-only; don't fail on macOS
        required = _IS_LINUX
        checks.append(_check_binary("apptainer", "apptainer", probe=["apptainer", "--version"], required=required))
    if target in {"all", "qemu"}:
        # The `qemu` runner executes qemu-system-x86_64 and qemu-img inside the
        # Apptainer container, so no host-level qemu binaries are required.
        # adb is only consulted for Android envs and has a bundled fallback.
        checks.append(_check_binary("adb", "adb", probe=["adb", "version"], required=False))
    if target in {"all", "qemu_native"}:
        checks.append(_check_binary("qemu_system", "qemu-system-x86_64", probe=["qemu-system-x86_64", "--version"]))
        checks.append(_check_binary("qemu_img", "qemu-img", probe=["qemu-img", "--version"]))
    if target in {"all", "avd"}:
        # The `avd` runner bundles its own adb/emulator under
        # ~/.cache/gym-anything/android-sdk/, so host binaries are optional.
        checks.append(_check_binary("adb", "adb", probe=["adb", "version"], required=False))
        checks.append(_check_binary("emulator", "emulator", probe=["emulator", "-version"], required=False))
    if target in {"all", "avf"}:
        checks.append(_check_binary("vfkit", "vfkit", probe=["vfkit", "--version"]))
        checks.append(_check_binary("gvproxy", "gvproxy"))
        checks.append(_check_binary("qemu_img", "qemu-img", probe=["qemu-img", "--version"]))
    if target in {"all", "avd_native"}:
        checks.append(_check_binary("adb", "adb", probe=["adb", "version"]))
        checks.append(_check_binary("emulator", "emulator", probe=["emulator", "-version"]))
    if target in {"all", "apptainer", "qemu", "avd"}:
        checks.append(_check_binary("ffmpeg", "ffmpeg", probe=["ffmpeg", "-version"], required=False))
    if target == "local":
        checks.append(DoctorCheck(name="local_runner", ok=True, detail="LocalRunner has no external system prerequisites"))

    # When no specific runner is requested, the user just wants to know "is
    # this machine usable?" Individual binary checks become diagnostic (WARN)
    # and the overall verdict is driven by a single runner_availability check:
    # the host is OK as long as at least one runner is READY.
    if target == "all":
        checks = [
            DoctorCheck(name=c.name, ok=c.ok, detail=c.detail, required=False)
            for c in checks
        ]
        statuses = get_runner_status()
        any_ready = any(s.get("available") for s in statuses.values())
        detail = (
            "at least one runner is READY"
            if any_ready
            else "no runner is READY — see Runner Status for missing deps"
        )
        checks.append(DoctorCheck(
            name="runner_availability",
            ok=any_ready,
            detail=detail,
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

# Which binaries each runner needs on the host.
# Runners built on Apptainer (qemu, avd, apptainer) only need `apptainer` on
# the host — qemu-system-*, qemu-img, adb, emulator etc. live inside the SIF.
_RUNNER_DEPS: Dict[str, List[str]] = {
    "docker": ["docker"],
    "qemu": ["apptainer"],
    "qemu_native": ["qemu-img", "mkisofs"],  # qemu-system-* auto-detected
    "avf": ["vfkit", "gvproxy", "qemu-img", "mkisofs"],
    "avd": ["apptainer"],
    "avd_native": ["adb"],
    "apptainer": ["apptainer"],
    "local": [],
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


def get_runner_status() -> Dict[str, Dict]:
    """Get status of all runners with dependency info."""
    import os

    results = {}
    for runner_key, deps in _RUNNER_DEPS.items():
        # Platform check
        if runner_key == "avf" and not _IS_MACOS:
            results[runner_key] = {"available": False, "reason": "macOS only", "deps": {}}
            continue
        if runner_key in ("qemu", "avd") and _IS_MACOS:
            results[runner_key] = {"available": False, "reason": "requires Apptainer (Linux only)", "deps": {}}
            continue
        if runner_key == "apptainer" and _IS_MACOS:
            results[runner_key] = {"available": False, "reason": "Linux only", "deps": {}}
            continue

        dep_status = {}
        all_ok = True
        for dep in deps:
            found = shutil.which(dep)
            if dep == "docker":
                # Docker needs both the CLI and a running daemon.
                daemon_up = _docker_daemon_alive() if found else False
                if found and not daemon_up:
                    # CLI is installed but daemon isn't responding: report it
                    # as a separate "docker-daemon" missing dep so the hint is
                    # actionable ("start the daemon" not "install docker").
                    dep_status["docker-daemon"] = {
                        "installed": False,
                        "path": None,
                        "desc": "Docker daemon not reachable",
                        "install": (
                            "open -a Docker" if _IS_MACOS else "sudo systemctl start docker"
                        ),
                    }
                    all_ok = False
                    continue
                available = found is not None and daemon_up
                dep_status[dep] = {
                    "installed": available,
                    "path": found,
                    "desc": _INSTALL_HINTS.get(dep, {}).get("desc", ""),
                    "install": _INSTALL_HINTS.get(dep, {}).get("macos" if _IS_MACOS else "linux", ""),
                }
                if not available:
                    all_ok = False
                continue
            dep_status[dep] = {
                "installed": found is not None,
                "path": found,
                "desc": _INSTALL_HINTS.get(dep, {}).get("desc", ""),
                "install": _INSTALL_HINTS.get(dep, {}).get("macos" if _IS_MACOS else "linux", ""),
            }
            if not found:
                all_ok = False

        # Special: qemu_native needs either qemu-system-x86_64 or qemu-system-aarch64
        if runner_key == "qemu_native":
            if _IS_MACOS and _IS_ARM:
                qemu_bin = "qemu-system-aarch64"
            else:
                qemu_bin = "qemu-system-x86_64"
            found = shutil.which(qemu_bin)
            dep_status[qemu_bin] = {
                "installed": found is not None,
                "path": found,
                "desc": _INSTALL_HINTS.get(qemu_bin, {}).get("desc", ""),
                "install": _INSTALL_HINTS.get(qemu_bin, {}).get("macos" if _IS_MACOS else "linux", ""),
            }
            if not found:
                all_ok = False

        # Special: avf needs base image or ability to build
        if runner_key == "avf":
            from pathlib import Path as _Path
            base = _Path.home() / ".cache/gym-anything/qemu/avf/base_ubuntu_gnome_arm64.raw"
            dep_status["base_image"] = {
                "installed": base.exists(),
                "path": str(base) if base.exists() else None,
                "desc": "ARM64 Ubuntu base image (auto-built on first run)",
                "install": "Built automatically on first run (~5 min)",
            }

        results[runner_key] = {"available": all_ok, "deps": dep_status}
    return results


def get_recommended_runner(runner_status: Optional[Dict[str, Dict]] = None) -> Optional[str]:
    """Pick the recommended runner for this platform.

    Always returns the top-preference runner for the platform, regardless of
    whether its deps are installed — doctor offers to install it when missing.
    This keeps the recommendation stable (e.g. macOS always gets `avf`) rather
    than drifting to whichever runner happens to be ready first.
    """
    statuses = runner_status if runner_status is not None else get_runner_status()

    if _IS_MACOS and _IS_ARM:
        preferences = ["avf", "qemu_native", "docker"]
    elif _IS_MACOS:
        preferences = ["qemu_native", "docker"]
    elif _IS_LINUX:
        preferences = ["qemu", "docker"]
    else:
        preferences = ["docker"]

    # Return the first preference that isn't blocked by platform.
    for runner in preferences:
        status = statuses.get(runner)
        if status is not None and not status.get("reason"):
            return runner
    return None


def render_doctor_rich(report: DoctorReport) -> str:
    """Render a user-friendly doctor output with runner status and install hints."""
    lines: List[str] = []

    # Platform info
    lines.append(f"Platform: {_sys.platform} ({_platform.machine()})")
    lines.append("")

    # Runner status
    runner_status = get_runner_status()

    # Determine recommended runner
    recommended = None
    if _IS_MACOS and _IS_ARM:
        for r in ["avf", "qemu_native", "docker"]:
            if runner_status.get(r, {}).get("available"):
                recommended = r
                break
        if not recommended:
            recommended = "avf"  # Recommend even if not yet installed
    elif _IS_MACOS:
        for r in ["qemu_native", "docker"]:
            if runner_status.get(r, {}).get("available"):
                recommended = r
                break
    elif _IS_LINUX:
        for r in ["qemu", "docker"]:
            if runner_status.get(r, {}).get("available"):
                recommended = r
                break

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
    "DoctorCheck",
    "DoctorReport",
    "get_recommended_runner",
    "get_runner_status",
    "render_doctor_text",
    "run_doctor",
    "scan_verifier_imports",
]
