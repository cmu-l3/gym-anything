"""Memory diff service — wraps `git diff HEAD` over the memory roots.

Output is a structured list of file-level diffs the UI can render as
the "Memory Diffs" side panel. Pending (uncommitted) changes appear
here, which includes every `expert_feedback.md` append the console
has made since the last commit.
"""

from __future__ import annotations

import logging
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

from ..config import Settings


logger = logging.getLogger("expert_console.memory_diff")


# ----------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------


@dataclass
class DiffHunk:
    header: str  # the @@ ... @@ line
    lines: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {"header": self.header, "lines": list(self.lines)}


@dataclass
class FileDiff:
    rel_path: str
    status: str  # "modified" | "added" | "deleted" | "renamed"
    old_path: str | None
    additions: int
    deletions: int
    hunks: list[DiffHunk] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "rel_path": self.rel_path,
            "status": self.status,
            "old_path": self.old_path,
            "additions": self.additions,
            "deletions": self.deletions,
            "hunks": [h.to_dict() for h in self.hunks],
        }


@dataclass
class MemoryDiff:
    files: list[FileDiff] = field(default_factory=list)
    base_ref: str = "HEAD"

    @property
    def total_additions(self) -> int:
        return sum(f.additions for f in self.files)

    @property
    def total_deletions(self) -> int:
        return sum(f.deletions for f in self.files)

    def to_dict(self) -> dict:
        return {
            "base_ref": self.base_ref,
            "total_additions": self.total_additions,
            "total_deletions": self.total_deletions,
            "files": [f.to_dict() for f in self.files],
        }


class MemoryDiffError(RuntimeError):
    """Raised when git is unavailable or fails."""


# ----------------------------------------------------------------------
# Service
# ----------------------------------------------------------------------


def _diff_over_paths(
    repo_root: Path, paths: list[Path]
) -> MemoryDiff:
    """Run `git diff HEAD` over the given paths, parse, and include
    untracked files inside those paths as synthetic 'added' entries.
    """
    if not _has_git(repo_root):
        raise MemoryDiffError(
            "`git` binary is not on PATH — required to compute diffs."
        )
    rel_paths = [p.resolve().relative_to(repo_root).as_posix() for p in paths]
    cmd = [
        "git",
        "diff",
        "--no-color",
        "--patch",
        "HEAD",
        "--",
        *rel_paths,
    ]
    result = subprocess.run(
        cmd,
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode not in (0, 1):
        raise MemoryDiffError(
            f"git diff failed (exit {result.returncode}): {result.stderr.strip()}"
        )
    files = _parse_unified_diff(result.stdout)
    diff = MemoryDiff(files=files, base_ref="HEAD")
    for path in _list_untracked(repo_root, rel_paths):
        try:
            content = (repo_root / path).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        file_diff = FileDiff(
            rel_path=path,
            status="added",
            old_path=None,
            additions=content.count("\n") + (1 if content and not content.endswith("\n") else 0),
            deletions=0,
            hunks=[
                DiffHunk(
                    header=f"@@ -0,0 +1,{content.count(chr(10)) + 1} @@",
                    lines=[f"+{line}" for line in content.splitlines()],
                )
            ],
        )
        diff.files.append(file_diff)
    return diff


def _has_git(repo_root: Path) -> bool:
    try:
        subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=str(repo_root),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def _list_untracked(repo_root: Path, prefixes: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "--", *prefixes],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise MemoryDiffError(
            f"git ls-files failed (exit {result.returncode}): {result.stderr.strip()}"
        )
    return [line for line in result.stdout.splitlines() if line.strip()]


class MemoryDiffService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.repo_root = settings.repo_root.resolve()
        self.paths = [p.resolve() for p in settings.memory_paths_to_watch()]

    def get_diff(self, env_dir: str | None = None) -> MemoryDiff:
        """Return the pending diff over memory paths.

        If `env_dir` is provided, the result also includes per-env
        shards (files whose name matches the env dir).
        """
        diff = _diff_over_paths(self.repo_root, self.paths)
        if env_dir is not None:
            diff.files = [
                f
                for f in diff.files
                if env_dir in f.rel_path
                or "expert_feedback" in f.rel_path
                or "audit_" in f.rel_path
            ]
        return diff

    # ------------------------------------------------------------------
    # Internals (preserved for backward compat with existing tests)
    # ------------------------------------------------------------------

    def _has_git(self) -> bool:
        try:
            subprocess.run(
                ["git", "rev-parse", "--is-inside-work-tree"],
                cwd=str(self.repo_root),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )
            return True
        except (FileNotFoundError, subprocess.CalledProcessError):
            return False

    def _list_untracked(self, prefixes: Iterable[str]) -> list[str]:
        return _list_untracked(self.repo_root, list(prefixes))


class EnvDiffService:
    """Git diff over an env folder + its audit report.

    Used by the "Pending Changes — Environment" section of the UI side
    panel so the expert can see exactly what the pipeline produced for
    the env they're inspecting.
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.repo_root = settings.repo_root.resolve()

    def get_diff(self, env_dir: str) -> MemoryDiff:
        if not env_dir:
            raise MemoryDiffError("env_dir is required for env diff.")
        env_root = (self.settings.environments_dir / env_dir).resolve()
        if not env_root.is_dir():
            raise MemoryDiffError(f"Unknown env_dir: {env_dir}")
        watched: list[Path] = [env_root]
        audit_file = self.settings.audits_dir / f"audit_{env_dir}.md"
        if audit_file.parent.is_dir():
            # Pass the audits dir; git will scope by the file inside it.
            watched.append(audit_file.parent)
        return _diff_over_paths(self.repo_root, watched)


# ----------------------------------------------------------------------
# Diff parsing
# ----------------------------------------------------------------------


def _parse_unified_diff(text: str) -> list[FileDiff]:
    files: list[FileDiff] = []
    if not text.strip():
        return files

    current: FileDiff | None = None
    current_hunk: DiffHunk | None = None

    for line in text.splitlines():
        if line.startswith("diff --git "):
            if current is not None:
                if current_hunk is not None:
                    current.hunks.append(current_hunk)
                    current_hunk = None
                files.append(current)
            parts = line.split(" ")
            a_path = parts[2][2:] if parts[2].startswith("a/") else parts[2]
            b_path = parts[3][2:] if parts[3].startswith("b/") else parts[3]
            current = FileDiff(
                rel_path=b_path,
                status="modified",
                old_path=a_path if a_path != b_path else None,
                additions=0,
                deletions=0,
            )
            continue
        if current is None:
            continue
        if line.startswith("new file mode"):
            current.status = "added"
            current.old_path = None
        elif line.startswith("deleted file mode"):
            current.status = "deleted"
        elif line.startswith("rename from "):
            current.status = "renamed"
            current.old_path = line[len("rename from "):]
        elif line.startswith("@@"):
            if current_hunk is not None:
                current.hunks.append(current_hunk)
            current_hunk = DiffHunk(header=line, lines=[])
        elif current_hunk is not None and (
            line.startswith("+") or line.startswith("-") or line.startswith(" ")
        ):
            if line.startswith("+++") or line.startswith("---"):
                continue
            current_hunk.lines.append(line)
            if line.startswith("+"):
                current.additions += 1
            elif line.startswith("-"):
                current.deletions += 1

    if current is not None:
        if current_hunk is not None:
            current.hunks.append(current_hunk)
        files.append(current)
    return files


__all__ = [
    "MemoryDiffService",
    "EnvDiffService",
    "MemoryDiffError",
    "MemoryDiff",
    "FileDiff",
    "DiffHunk",
]
