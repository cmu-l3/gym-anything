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


def _run_command(command: List[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, capture_output=True, text=True, timeout=10)


def _check_binary(name: str, binary: str, *, probe: Optional[List[str]] = None, required: bool = True) -> DoctorCheck:
    resolved = _command_available(binary)
    if not resolved:
        return DoctorCheck(name=name, ok=False, detail=f"{binary} not found on PATH", required=required)
    if probe is None:
        return DoctorCheck(name=name, ok=True, detail=f"{binary} -> {resolved}", required=required)
    try:
        result = _run_command(probe)
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
    if target in {"all", "docker", "browser"}:
        checks.append(_check_binary("docker_cli", "docker", probe=["docker", "version", "--format", "{{.Client.Version}}"]))
        checks.append(_check_binary("docker_daemon", "docker", probe=["docker", "info"]))
    if target in {"all", "qemu", "avd", "apptainer"}:
        checks.append(_check_binary("apptainer", "apptainer", probe=["apptainer", "--version"]))
    if target in {"all", "qemu"}:
        checks.append(_check_binary("qemu_system", "qemu-system-x86_64", probe=["qemu-system-x86_64", "--version"]))
        checks.append(_check_binary("qemu_img", "qemu-img", probe=["qemu-img", "--version"]))
        checks.append(_check_binary("adb", "adb", probe=["adb", "version"], required=False))
    if target in {"all", "avd"}:
        checks.append(_check_binary("adb", "adb", probe=["adb", "version"]))
        checks.append(_check_binary("emulator", "emulator", probe=["emulator", "-version"]))
    if target in {"all", "apptainer", "qemu", "avd"}:
        checks.append(_check_binary("ffmpeg", "ffmpeg", probe=["ffmpeg", "-version"], required=False))
    if target == "local":
        checks.append(DoctorCheck(name="local_runner", ok=True, detail="LocalRunner has no external system prerequisites"))
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


__all__ = [
    "DoctorCheck",
    "DoctorReport",
    "render_doctor_text",
    "run_doctor",
    "scan_verifier_imports",
]
