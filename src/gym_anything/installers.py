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
    """A sequence of install steps that set up a runner.

    When `manual_only` is set, there are no commands we can run for the user
    (e.g. `module load` is a shell function, not a binary). The UI should
    render `manual_only` as guidance and skip the install prompt.
    """

    runner: str
    summary: str
    steps: List[InstallStep] = field(default_factory=list)
    prereq_note: Optional[str] = None
    manual_only: Optional[str] = None


def get_install_plan(runner: str) -> Optional[InstallPlan]:
    """Return the install plan the runner class declares, or None.

    Plans are per-party facts (law L1): each runner class provides its own
    via ``install_plan()``; this resolves the key and asks.
    """
    from .runtime.runners import registry as runner_registry

    try:
        cls = runner_registry.resolve_runner_class(runner)
    except Exception:
        return None
    if cls is None:
        return None
    try:
        return cls.install_plan()
    except Exception:
        return None


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


def _has_module_system() -> bool:
    """Detect LMOD / environment modules (common on HPC clusters)."""
    return bool(
        os.environ.get("MODULEPATH")
        or os.environ.get("LMOD_CMD")
        or os.environ.get("MODULESHOME")
    )


def _module_has_apptainer() -> bool:
    """Return True if the cluster exposes apptainer (or singularity) as a module."""
    if not _has_module_system():
        return False
    try:
        # `module` is a shell function; a login shell sources it from
        # /etc/profile.d/ on most clusters.
        result = subprocess.run(
            ["bash", "-lc", "module avail apptainer singularity 2>&1 || true"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        return False
    combined = (result.stdout + result.stderr).lower()
    if "no modules" in combined or "no module(s)" in combined:
        return False
    return "apptainer" in combined or "singularity" in combined


def apptainer_install_plan(runner_key: str) -> InstallPlan:
    """Shared Apptainer install plan (module system / conda / apt / manual).

    Used by every Apptainer-based runner class; parameterized by the key
    so the plan is attributed to the runner that asked.
    """
    # 1. HPC cluster with a module system — no install needed.
    if _module_has_apptainer():
        return InstallPlan(
            runner=runner_key,
            summary="Apptainer via cluster module system (no install needed)",
            manual_only=(
                "This host exposes Apptainer via its module system. Load it in your shell:\n"
                "    module load apptainer\n"
                "Then re-run `gym-anything doctor` in the same shell. If the module name\n"
                "differs (e.g. `apptainer/1.3`, `singularity`), check `module avail`."
            ),
        )

    # 2. conda — rootless install, works for SLURM users without sudo.
    if shutil.which("conda") is not None:
        return InstallPlan(
            runner=runner_key,
            summary="Apptainer via conda-forge (rootless, no sudo)",
            prereq_note="Installs into your active conda environment.",
            steps=[
                InstallStep(
                    description="Install apptainer from conda-forge",
                    command=["conda", "install", "-y", "-c", "conda-forge", "apptainer"],
                    requires=["conda"],
                    skip_if="apptainer",
                ),
            ],
        )

    # 3. Debian/Ubuntu with sudo.
    if shutil.which("apt-get") is not None:
        return InstallPlan(
            runner=runner_key,
            summary="Apptainer via apt (Debian/Ubuntu, uses sudo)",
            prereq_note="Uses the Apptainer PPA. On clusters, ask your admin about `module load` instead.",
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

    # 4. No automatic path — point at docs.
    return InstallPlan(
        runner=runner_key,
        summary="Apptainer (manual install required)",
        manual_only=(
            "No automatic install path detected on this host.\n"
            "  - On a cluster, ask your admin about `module load apptainer`.\n"
            "  - Manual install: https://apptainer.org/docs/admin/main/installation.html"
        ),
    )


__all__ = [
    "InstallPlan",
    "InstallStep",
    "apptainer_install_plan",
    "get_install_plan",
    "run_install_plan",
]
