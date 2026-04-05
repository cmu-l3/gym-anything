"""Per-runner interactive install plans used by `gym-anything doctor`.

Doctor recommends a runner for the current platform, then offers to install
its dependencies. Each plan is a sequence of explicit steps: concrete
commands, prerequisite binaries, and skip-if conditions. Plans are
deliberately boring — no hidden magic, so a user can read the steps and
run them by hand if they prefer.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional

_IS_MACOS = sys.platform == "darwin"
_IS_LINUX = sys.platform == "linux"
_IS_ARM = (os.uname().machine in ("arm64", "aarch64")) if hasattr(os, "uname") else False


@dataclass(frozen=True)
class InstallStep:
    """A single install command in a plan."""

    description: str
    command: List[str]
    requires: List[str] = field(default_factory=list)  # binaries that must already exist
    skip_if: Optional[str] = None  # if this binary is on PATH, skip the step
    shell: bool = False  # pass command[0] to /bin/sh -c (for pipes/redirects)

    def should_skip(self) -> bool:
        return self.skip_if is not None and shutil.which(self.skip_if) is not None

    def missing_prereqs(self) -> List[str]:
        return [r for r in self.requires if shutil.which(r) is None]

    def render(self) -> str:
        if self.shell:
            return self.command[0]
        return " ".join(self.command)


@dataclass(frozen=True)
class InstallPlan:
    """A sequence of install steps that set up a runner."""

    runner: str
    summary: str
    steps: List[InstallStep]
    prereq_note: Optional[str] = None


def get_install_plan(runner: str) -> Optional[InstallPlan]:
    """Return the install plan for the given runner on this platform, or None."""
    builder = _PLAN_BUILDERS.get(runner)
    if builder is None:
        return None
    return builder()


def run_install_plan(plan: InstallPlan, *, dry_run: bool = False) -> bool:
    """Execute the plan's steps sequentially. Returns True if all steps succeed."""
    for step in plan.steps:
        if step.should_skip():
            print(f"  [skip] {step.description} (already present)")
            continue
        missing = step.missing_prereqs()
        if missing:
            print(f"  [fail] {step.description}: missing prerequisite(s) {', '.join(missing)}")
            return False
        print(f"  [run ] {step.description}")
        print(f"         $ {step.render()}")
        if dry_run:
            continue
        try:
            if step.shell:
                result = subprocess.run(step.command[0], shell=True)
            else:
                result = subprocess.run(step.command)
        except KeyboardInterrupt:
            print("\n  [abort] interrupted by user")
            return False
        if result.returncode != 0:
            print(f"  [fail] step exited with code {result.returncode}")
            return False
    return True


# --- Plan builders ---


def _avf_plan() -> InstallPlan:
    """macOS: Apple Virtualization Framework + gvproxy + qemu-img + mkisofs."""
    gvproxy_asset = "gvproxy-darwin-arm64" if _IS_ARM else "gvproxy-darwin"
    gvproxy_url = (
        f"https://github.com/containers/gvisor-tap-vsock/releases/latest/download/{gvproxy_asset}"
    )
    return InstallPlan(
        runner="avf",
        summary="Apple Virtualization Framework (recommended for macOS)",
        prereq_note="Requires Homebrew (https://brew.sh/).",
        steps=[
            InstallStep(
                description="Install vfkit via Homebrew",
                command=["brew", "install", "vfkit"],
                requires=["brew"],
                skip_if="vfkit",
            ),
            InstallStep(
                description="Install qemu via Homebrew (for qemu-img)",
                command=["brew", "install", "qemu"],
                requires=["brew"],
                skip_if="qemu-img",
            ),
            InstallStep(
                description="Install cdrtools via Homebrew (for mkisofs)",
                command=["brew", "install", "cdrtools"],
                requires=["brew"],
                skip_if="mkisofs",
            ),
            InstallStep(
                description="Download gvproxy to /usr/local/bin (uses sudo)",
                command=[
                    f"sudo curl -fsSL -o /usr/local/bin/gvproxy {gvproxy_url} "
                    f"&& sudo chmod +x /usr/local/bin/gvproxy"
                ],
                shell=True,
                requires=["curl", "sudo"],
                skip_if="gvproxy",
            ),
        ],
    )


def _qemu_native_plan() -> InstallPlan:
    """macOS: native QEMU (no Apptainer)."""
    return InstallPlan(
        runner="qemu_native",
        summary="Native QEMU for macOS (no Apptainer)",
        prereq_note="Requires Homebrew.",
        steps=[
            InstallStep(
                description="Install qemu via Homebrew",
                command=["brew", "install", "qemu"],
                requires=["brew"],
                skip_if="qemu-img",
            ),
            InstallStep(
                description="Install cdrtools via Homebrew (for mkisofs)",
                command=["brew", "install", "cdrtools"],
                requires=["brew"],
                skip_if="mkisofs",
            ),
        ],
    )


def _qemu_apptainer_plan() -> InstallPlan:
    """Linux: Apptainer-based QEMU runner."""
    return InstallPlan(
        runner="qemu",
        summary="Apptainer (runs QEMU inside a SIF container; no host-level QEMU needed)",
        prereq_note=(
            "On HPC clusters (SLURM), Apptainer is often already available — "
            "try `module load apptainer` before running this. "
            "These steps use sudo and the Apptainer PPA (Debian/Ubuntu)."
        ),
        steps=[
            InstallStep(
                description="Enable the Apptainer PPA",
                command=["sudo", "add-apt-repository", "-y", "ppa:apptainer/ppa"],
                requires=["sudo", "add-apt-repository"],
                skip_if="apptainer",
            ),
            InstallStep(
                description="Refresh apt package index",
                command=["sudo", "apt-get", "update"],
                requires=["sudo", "apt-get"],
                skip_if="apptainer",
            ),
            InstallStep(
                description="Install apptainer via apt",
                command=["sudo", "apt-get", "install", "-y", "apptainer"],
                requires=["sudo", "apt-get"],
                skip_if="apptainer",
            ),
        ],
    )


def _docker_plan() -> InstallPlan:
    if _IS_MACOS:
        return InstallPlan(
            runner="docker",
            summary="Docker Desktop for macOS",
            prereq_note="Requires Homebrew. You still need to open Docker.app once to start the daemon.",
            steps=[
                InstallStep(
                    description="Install Docker Desktop via Homebrew",
                    command=["brew", "install", "--cask", "docker"],
                    requires=["brew"],
                    skip_if="docker",
                ),
            ],
        )
    return InstallPlan(
        runner="docker",
        summary="Docker Engine (via get.docker.com)",
        prereq_note="Runs the official convenience script with sudo. Read it first if you're cautious.",
        steps=[
            InstallStep(
                description="Install Docker via get.docker.com",
                command=["curl -fsSL https://get.docker.com | sh"],
                shell=True,
                requires=["curl", "sudo"],
                skip_if="docker",
            ),
        ],
    )


_PLAN_BUILDERS: Dict[str, Callable[[], InstallPlan]] = {
    "avf": _avf_plan,
    "qemu_native": _qemu_native_plan,
    "qemu": _qemu_apptainer_plan,
    "docker": _docker_plan,
}


__all__ = [
    "InstallPlan",
    "InstallStep",
    "get_install_plan",
    "run_install_plan",
]
