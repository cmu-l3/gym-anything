"""Memory service — read & append to the pipelines' memory folders.

Two pipelines share the structure but with different prompts:

  creation_audit/memory/
    audit_prompt.md
    audit_expert_feedback.md            <- expert feedback for audit
    env_creation_notes/
      00..14_*.md                       <- general notes
      expert_feedback.md                <- expert feedback for creator
    specific_env_notes/                 <- per-env shards (optional)
    <env>_notes.md                      <- alternative per-env shard layout

  propose_and_amplify/memory/
    task_creation_notes/
      00..14_*.md                       <- general notes
      expert_feedback.md                <- expert feedback for proposer
      slicer3d_*.md                     <- per-env / per-task shards

The service exposes a tier-aware listing (GENERAL vs SPECIFIC), read of
any file under the memory roots, and an `append_expert_entry()` that
both pipelines' prompts pick up automatically.
"""

from __future__ import annotations

import enum
import logging
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from ..config import Settings


logger = logging.getLogger("expert_console.memory")


# ----------------------------------------------------------------------
# Public types
# ----------------------------------------------------------------------


class MemoryTier(str, enum.Enum):
    GENERAL = "general"
    SPECIFIC = "specific"


class FeedbackTarget(str, enum.Enum):
    """Which prompt the expert feedback feeds into."""

    CREATOR = "creator"  # env creation prompt
    AUDIT = "audit"  # audit prompt
    PROPOSER = "proposer"  # task creation prompt


@dataclass
class MemoryFile:
    rel_path: str
    name: str
    tier: MemoryTier
    pipeline: str  # "creation_audit" | "propose_and_amplify"
    is_expert_feedback: bool
    size_bytes: int
    env_dir: str | None = None
    snippet: str | None = None

    def to_dict(self) -> dict:
        return {
            "rel_path": self.rel_path,
            "name": self.name,
            "tier": self.tier.value,
            "pipeline": self.pipeline,
            "is_expert_feedback": self.is_expert_feedback,
            "size_bytes": self.size_bytes,
            "env_dir": self.env_dir,
            "snippet": self.snippet,
        }


@dataclass
class MemoryListing:
    general: list[MemoryFile] = field(default_factory=list)
    specific: list[MemoryFile] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "general": [m.to_dict() for m in self.general],
            "specific": [m.to_dict() for m in self.specific],
        }


@dataclass
class EntryRecord:
    rel_path: str
    anchor: str  # the markdown anchor (header text) for the entry
    timestamp: str

    def to_dict(self) -> dict:
        return {
            "rel_path": self.rel_path,
            "anchor": self.anchor,
            "timestamp": self.timestamp,
        }


# ----------------------------------------------------------------------
# Errors
# ----------------------------------------------------------------------


class MemoryError(RuntimeError):
    """Raised on invalid memory access (path traversal, missing file)."""


# ----------------------------------------------------------------------
# Service
# ----------------------------------------------------------------------


_SLUG_RE = re.compile(r"[^a-zA-Z0-9]+")


def _slugify(text: str) -> str:
    return _SLUG_RE.sub("-", text.strip().lower()).strip("-")[:80] or "note"


def _iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _looks_env_specific(
    path: Path, root: Path, env_dirs: set[str]
) -> str | None:
    """Return the env_dir this memory file belongs to, if any.

    Recognised patterns (in priority order):

      1. The file lives inside `<root>/.../<env_dir>/...` — the
         creation_audit memory has `env_creation_notes/specific_env_notes/<env_dir>/`
         per-env shards. Any file under a directory whose name matches
         an env_dir counts.

      2. The file's name matches `<env_dir>.md`.

      3. The file's name matches `<bare>.md` or `<bare>_*.md` where
         `<bare>` is the env_dir with `_env` stripped (e.g.
         `openemr_notes.md` for env `openemr_env`).
    """
    try:
        rel = path.relative_to(root)
    except ValueError:
        rel = path

    # 1) any ancestor directory name matches an env_dir
    for parent in rel.parents:
        lower = parent.name.lower()
        if lower in env_dirs:
            return lower
        bare = lower.removesuffix("_env")
        if bare and (bare + "_env") in env_dirs:
            return bare + "_env"

    base = path.stem.lower()
    if base in env_dirs:
        return base

    # 2/3) bare-name matching ("openemr_notes.md" -> "openemr_env")
    bare_to_env = {e.removesuffix("_env"): e for e in env_dirs if e != "env"}
    if base in bare_to_env:
        return bare_to_env[base]
    if base.endswith("_notes"):
        stripped = base[:-6]
        if stripped in bare_to_env:
            return bare_to_env[stripped]
        if stripped in env_dirs:
            return stripped
    for env in env_dirs:
        if base.startswith(env + "_"):
            return env
    for bare, env in bare_to_env.items():
        if bare and base.startswith(bare + "_"):
            return env
    return None


class MemoryService:
    """Read and write the pipelines' memory."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.repo_root = settings.repo_root.resolve()
        self.creation_root = settings.creation_audit_memory_dir.resolve()
        self.propose_root = settings.propose_amplify_memory_dir.resolve()
        if not self.creation_root.is_dir():
            raise MemoryError(
                f"creation_audit memory root missing: {self.creation_root}"
            )
        if not self.propose_root.is_dir():
            raise MemoryError(
                f"propose_and_amplify memory root missing: {self.propose_root}"
            )

    # ------------------------------------------------------------------
    # Listing
    # ------------------------------------------------------------------

    def list_memory(
        self, env_dir: str | None = None, *, snippet_chars: int = 600
    ) -> MemoryListing:
        env_dirs = self._known_env_dirs()
        listing = MemoryListing()
        for pipeline, root in (
            ("creation_audit", self.creation_root),
            ("propose_and_amplify", self.propose_root),
        ):
            for path in self._iter_memory_files(root):
                rel = path.resolve().relative_to(self.repo_root).as_posix()
                env_specific = _looks_env_specific(path, root, env_dirs)
                tier = MemoryTier.SPECIFIC if env_specific else MemoryTier.GENERAL
                is_expert = path.name == "expert_feedback.md" or (
                    path.name == "audit_expert_feedback.md"
                )
                if is_expert:
                    # Expert feedback files always show up under both
                    # tiers — they carry GLOBAL plus env-specific
                    # entries — but we surface them as general by
                    # default and let the env-specific view re-emit.
                    tier = MemoryTier.GENERAL
                file_entry = MemoryFile(
                    rel_path=rel,
                    name=path.name,
                    tier=tier,
                    pipeline=pipeline,
                    is_expert_feedback=is_expert,
                    size_bytes=path.stat().st_size,
                    env_dir=env_specific,
                    snippet=self._snippet(path, snippet_chars),
                )
                bucket = listing.general if tier is MemoryTier.GENERAL else listing.specific
                bucket.append(file_entry)

        if env_dir is not None:
            listing.specific = [m for m in listing.specific if m.env_dir == env_dir]

        listing.general.sort(key=lambda m: (m.pipeline, m.name))
        listing.specific.sort(key=lambda m: (m.pipeline, m.name))
        return listing

    def read_file(self, rel_path: str) -> str:
        path = self._resolve(rel_path)
        return path.read_text(encoding="utf-8")

    # ------------------------------------------------------------------
    # Append
    # ------------------------------------------------------------------

    def append_expert_entry(
        self,
        *,
        target: FeedbackTarget,
        memory_tier: MemoryTier,
        env_dir: str | None,
        task_id: str | None,
        body: str,
        suggest_checklist_change: bool,
    ) -> EntryRecord:
        """Append a new entry to the right expert_feedback file.

        Entry header format:
            ## <ts> — <env_dir>             (env picked + specific scope)
            ## <ts> — <env_dir> — global    (env picked + general scope)
            ## <ts> — GLOBAL                (no env picked)

        Notes:
          * The task_id is **never** auto-injected into the header — if the
            expert wants to call out a specific task, they put it in the
            feedback body. The dispatcher still uses task_id to route to
            the edit_task driver; the memory entry stays clean.
          * The env_dir is shown whenever picked, even if the scope is
            general — so the reader can see what triggered the note while
            also knowing it applies everywhere.
        """
        if memory_tier is MemoryTier.SPECIFIC and not env_dir:
            raise MemoryError(
                "SPECIFIC tier requires env_dir; got None."
            )
        if not body.strip():
            raise MemoryError("Feedback body cannot be empty.")

        path = self._expert_feedback_path(target)
        ts = _iso_now()

        if env_dir:
            if memory_tier is MemoryTier.GENERAL:
                header_target = f"{env_dir} — global"
                scope_for_anchor = f"{env_dir}-global"
            else:
                header_target = env_dir
                scope_for_anchor = env_dir
        else:
            header_target = "GLOBAL"
            scope_for_anchor = "global"

        first_line = body.strip().splitlines()[0]
        anchor = _slugify(f"{ts} {scope_for_anchor} {first_line[:80]}")
        header = f"## {ts} — {header_target}"

        block_lines = [
            "",
            header,
            "",
        ]
        if suggest_checklist_change:
            block_lines.append("**Proposed checklist change.** Treat this as an additional checklist item, not just guidance.")
            block_lines.append("")
        block_lines.append(body.strip())
        block_lines.append("")
        with path.open("a", encoding="utf-8") as fh:
            fh.write("\n".join(block_lines))

        rel = path.resolve().relative_to(self.repo_root).as_posix()
        return EntryRecord(rel_path=rel, anchor=anchor, timestamp=ts)

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _expert_feedback_path(self, target: FeedbackTarget) -> Path:
        if target is FeedbackTarget.CREATOR:
            return self.settings.expert_feedback_creation_path.resolve()
        if target is FeedbackTarget.AUDIT:
            return self.settings.expert_feedback_audit_path.resolve()
        if target is FeedbackTarget.PROPOSER:
            return self.settings.expert_feedback_propose_path.resolve()
        raise MemoryError(f"Unknown feedback target: {target}")  # pragma: no cover

    def _iter_memory_files(self, root: Path) -> Iterable[Path]:
        for path in sorted(root.rglob("*.md")):
            if not path.is_file():
                continue
            # Skip anything under a hidden dir.
            if any(part.startswith(".") for part in path.relative_to(root).parts):
                continue
            # Don't surface README-style chrome inside the memory root.
            yield path

    def _snippet(self, path: Path, n: int) -> str:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return ""
        text = text.strip()
        if len(text) <= n:
            return text
        return text[:n].rstrip() + "..."

    def _known_env_dirs(self) -> set[str]:
        envs_dir = self.settings.environments_dir
        if not envs_dir.is_dir():
            return set()
        return {
            p.name.lower()
            for p in envs_dir.iterdir()
            if p.is_dir() and not p.name.startswith((".", "__"))
        }

    def _resolve(self, rel_path: str) -> Path:
        candidate = (self.repo_root / rel_path).resolve()
        try:
            candidate.relative_to(self.repo_root)
        except ValueError as exc:
            raise MemoryError(f"Memory path escapes repo root: {rel_path}") from exc
        if not candidate.is_file():
            raise MemoryError(f"Memory file not found: {rel_path}")
        # Restrict to known memory roots.
        for root in (self.creation_root, self.propose_root):
            try:
                candidate.relative_to(root)
                return candidate
            except ValueError:
                continue
        raise MemoryError(
            f"Memory path is not under a known memory root: {rel_path}"
        )


__all__ = [
    "MemoryService",
    "MemoryError",
    "MemoryTier",
    "FeedbackTarget",
    "MemoryFile",
    "MemoryListing",
    "EntryRecord",
]
