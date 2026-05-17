"""Plain-English summary of what a pipeline run actually changed.

After `edit_task` / `edit_env` / `propose_and_amplify` finishes, the
expert wants to know — without reading the raw diff — whether the
agent addressed the original feedback. This service:

  1. Looks up the originating feedback message and the target env.
  2. Pulls the env-scoped git diff that materialised since the run
     started (modified + untracked files inside the env folder + its
     audit report).
  3. Asks GPT-5.4 (reasoning effort medium) to summarise the diff in
     plain English **and** explicitly judge whether the original
     feedback was addressed.

Cached by `(run_id, diff_signature)` so the same finished run isn't
re-summarized for free on every reload.
"""

from __future__ import annotations

import hashlib
import json
import logging
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from sqlalchemy.orm import sessionmaker

from ..config import Settings
from ..db import get_sessionmaker
from ..models import AgentRun, Feedback
from .memory_diff import EnvDiffService, MemoryDiffError
from .preferences import PreferencesService
from .summarize import (
    OpenAIBackend,
    SummarizationError,
    _RealOpenAIBackend,
)


logger = logging.getLogger("expert_console.changes_summary")


# ----------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------


@dataclass
class ChangesSummary:
    summary: str
    bullets: list[str]
    addressed_feedback: str  # "yes" | "partial" | "no" | "unclear"
    addressed_reason: str
    file_count: int
    additions: int
    deletions: int
    cached: bool
    model: str
    reasoning_effort: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class _DiffSnapshot:
    file_paths: list[str]
    additions: int
    deletions: int
    patch_text: str

    def signature(self) -> str:
        h = hashlib.sha256()
        h.update(self.patch_text.encode("utf-8", errors="replace"))
        return h.hexdigest()


class ChangesSummaryError(RuntimeError):
    """Raised on invalid summarization requests."""


# ----------------------------------------------------------------------
# Prompt
# ----------------------------------------------------------------------


_SYSTEM_PROMPT = """You are a technical writer summarising what a code-
generating AI agent just changed in response to an expert's feedback.

Your audience is the domain expert who wrote the original feedback.
They are NOT a software engineer. They want to know two things:

  1. What did the agent actually change, in concrete data-quality terms
     (what dataset names did it swap, what URLs did it cite, what
     real-world sources did it pull, what counts/scales did it touch)?
  2. Did the agent actually address the expert's original feedback?

Hard rules:
- Lead with one short paragraph naming the substantive change. **If
  data was changed, the data is the headline** — what was swapped,
  source URLs / dataset names, scale.
- Give 3-6 bullets covering: (a) data changes (datasets, sources, real
  vs synthetic), (b) code / script changes that flow from the data
  change, (c) verifier / checklist updates, (d) anything the agent
  added that wasn't in the feedback (good or bad), (e) anything from
  the feedback the agent skipped or missed.
- Set `addressed_feedback` to:
    * "yes"     — the change clearly satisfies the feedback
    * "partial" — some parts addressed, others skipped or weakened
    * "no"      — the change doesn't actually address the feedback
    * "unclear" — feedback was too vague or diff is too small to tell
  And explain that judgment in `addressed_reason` (1-2 sentences).
- Never invent details. If the diff cites a URL or dataset, name it
  verbatim. If something is unclear, say so.

Respond as a JSON object with exactly these keys:
  summary             (string, 1 short paragraph)
  bullets             (array of short strings, <= 22 words each)
  addressed_feedback  ("yes" | "partial" | "no" | "unclear")
  addressed_reason    (string, 1-2 sentences)
"""


def _user_prompt(
    *, feedback: str, env_dir: str, snapshot: _DiffSnapshot, command: list[str]
) -> str:
    return (
        f"Expert's original feedback:\n---\n{feedback.strip()}\n---\n\n"
        f"Target environment: {env_dir}\n"
        f"Driver invoked: {' '.join(command)}\n\n"
        f"Files changed ({snapshot.file_count if hasattr(snapshot, 'file_count') else len(snapshot.file_paths)}):\n"
        + "\n".join(f"  {p}" for p in snapshot.file_paths)
        + "\n\n"
        + "Unified git diff (env-scoped):\n---\n"
        + (snapshot.patch_text[:60_000] or "(no diff captured)")
        + ("\n[diff truncated]" if len(snapshot.patch_text) > 60_000 else "")
        + "\n---"
    )


# ----------------------------------------------------------------------
# Service
# ----------------------------------------------------------------------


class ChangesSummaryService:
    """Produce / cache a plain-English summary for a finished AgentRun."""

    def __init__(
        self,
        settings: Settings,
        *,
        backend: OpenAIBackend | None = None,
        preferences: PreferencesService | None = None,
        env_diff: EnvDiffService | None = None,
        session_factory: sessionmaker | None = None,
    ) -> None:
        self.settings = settings
        self._backend: OpenAIBackend | None = backend
        self._preferences = preferences
        self._env_diff = env_diff or EnvDiffService(settings)
        self._sessionmaker = session_factory or get_sessionmaker()
        self.cache_dir = settings.state_dir / "run_summaries"
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    @property
    def backend(self) -> OpenAIBackend:
        if self._backend is None:
            self._backend = _RealOpenAIBackend()
        return self._backend

    @property
    def preferences(self) -> PreferencesService:
        if self._preferences is None:
            self._preferences = PreferencesService(self.settings)
        return self._preferences

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------

    def summarize(self, run_id: str, *, force: bool = False) -> ChangesSummary:
        run_row, feedback_row, env_dir = self._load_run(run_id)
        command_list = self._command_list(run_row)
        snapshot = self._capture_diff(env_dir, run_started_at=run_row.started_at)

        cache_key = self._cache_key(run_id, snapshot.signature())
        cache_path = self.cache_dir / f"{cache_key}.json"
        if not force and cache_path.is_file():
            try:
                raw = json.loads(cache_path.read_text(encoding="utf-8"))
                return ChangesSummary(
                    summary=raw["summary"],
                    bullets=list(raw["bullets"]),
                    addressed_feedback=raw["addressed_feedback"],
                    addressed_reason=raw["addressed_reason"],
                    file_count=raw["file_count"],
                    additions=raw["additions"],
                    deletions=raw["deletions"],
                    cached=True,
                    model=raw.get("model", self.preferences.get().summarize_model),
                    reasoning_effort=raw.get(
                        "reasoning_effort",
                        self.preferences.get().summarize_reasoning_effort,
                    ),
                )
            except (OSError, json.JSONDecodeError, KeyError) as exc:
                raise ChangesSummaryError(
                    f"Corrupt cache at {cache_path}: {exc}"
                ) from exc

        if snapshot.file_paths == [] and snapshot.patch_text == "":
            result = ChangesSummary(
                summary="No file changes detected for this run.",
                bullets=[
                    "Run completed without modifying any files inside the env.",
                ],
                addressed_feedback="no",
                addressed_reason=(
                    "There are zero file changes inside the env folder, so the "
                    "agent didn't act on the feedback (or worked outside this env)."
                ),
                file_count=0,
                additions=0,
                deletions=0,
                cached=False,
                model=self.preferences.get().summarize_model,
                reasoning_effort=self.preferences.get().summarize_reasoning_effort,
            )
            self._write_cache(cache_path, result)
            return result

        prefs = self.preferences.get()
        feedback_text = (
            feedback_row.message if feedback_row else "(no feedback message stored)"
        )
        user_prompt = _user_prompt(
            feedback=feedback_text,
            env_dir=env_dir,
            snapshot=snapshot,
            command=command_list,
        )
        started = time.time()
        raw_response = self.backend.respond(
            model=prefs.summarize_model,
            reasoning_effort=prefs.summarize_reasoning_effort,
            system=_SYSTEM_PROMPT,
            user=user_prompt,
            timeout=float(prefs.summarize_timeout_sec),
        )
        elapsed = time.time() - started
        logger.info("changes_summary run=%s took=%.2fs", run_id, elapsed)

        parsed = _parse_response(raw_response)
        result = ChangesSummary(
            summary=parsed["summary"],
            bullets=parsed["bullets"],
            addressed_feedback=parsed["addressed_feedback"],
            addressed_reason=parsed["addressed_reason"],
            file_count=len(snapshot.file_paths),
            additions=snapshot.additions,
            deletions=snapshot.deletions,
            cached=False,
            model=prefs.summarize_model,
            reasoning_effort=prefs.summarize_reasoning_effort,
        )
        self._write_cache(cache_path, result)
        return result

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _load_run(self, run_id: str) -> tuple[AgentRun, Feedback | None, str]:
        with self._sessionmaker() as db:
            run = db.get(AgentRun, run_id)
            if run is None:
                raise ChangesSummaryError(f"Run not found: {run_id}")
            feedback = (
                db.get(Feedback, run.feedback_id) if run.feedback_id else None
            )
            env_dir = (
                (feedback.env_dir if feedback else None)
                or (run.session.env_dir if run.session else None)
            )
            if not env_dir:
                raise ChangesSummaryError(
                    f"Run {run_id} has no associated env_dir; cannot diff."
                )
            db.expunge(run)
            if feedback is not None:
                db.expunge(feedback)
            return run, feedback, env_dir

    def _command_list(self, run: AgentRun) -> list[str]:
        try:
            data = json.loads(run.command or "[]")
            if isinstance(data, list):
                return [str(x) for x in data]
        except (TypeError, json.JSONDecodeError):
            pass
        return []

    def _capture_diff(self, env_dir: str, *, run_started_at) -> _DiffSnapshot:
        try:
            diff = self._env_diff.get_diff(env_dir)
        except MemoryDiffError as exc:
            raise ChangesSummaryError(f"Diff capture failed: {exc}") from exc

        # Re-stringify the diff in a stable form for the LLM.
        chunks: list[str] = []
        file_paths: list[str] = []
        additions = 0
        deletions = 0
        for f in diff.files:
            file_paths.append(f.rel_path)
            additions += f.additions
            deletions += f.deletions
            chunks.append(f"diff --git a/{f.rel_path} b/{f.rel_path}")
            chunks.append(f"status: {f.status}")
            chunks.append(f"+{f.additions} -{f.deletions}")
            for hunk in f.hunks:
                chunks.append(hunk.header)
                for line in hunk.lines:
                    chunks.append(line)
            chunks.append("")
        return _DiffSnapshot(
            file_paths=file_paths,
            additions=additions,
            deletions=deletions,
            patch_text="\n".join(chunks),
        )

    def _cache_key(self, run_id: str, diff_sig: str) -> str:
        h = hashlib.sha256()
        h.update(run_id.encode("utf-8"))
        h.update(b"\x00")
        h.update(diff_sig.encode("utf-8"))
        prefs = self.preferences.get()
        h.update(b"\x00")
        h.update(prefs.summarize_model.encode("utf-8"))
        h.update(b"\x00")
        h.update(prefs.summarize_reasoning_effort.encode("utf-8"))
        return h.hexdigest()

    def _write_cache(self, path: Path, result: ChangesSummary) -> None:
        payload = result.to_dict()
        payload["created_at"] = time.time()
        tmp = path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        tmp.replace(path)


# ----------------------------------------------------------------------
# Response parsing
# ----------------------------------------------------------------------


def _parse_response(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[1] if "\n" in cleaned else cleaned[3:]
        if cleaned.rstrip().endswith("```"):
            cleaned = cleaned.rstrip()[:-3]
    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise ChangesSummaryError(
            f"changes-summary model did not return valid JSON. Got: {text!r}"
        ) from exc

    summary = data.get("summary")
    bullets = data.get("bullets")
    addressed = data.get("addressed_feedback")
    reason = data.get("addressed_reason")
    if not isinstance(summary, str) or not summary.strip():
        raise ChangesSummaryError("summary missing or empty in response")
    if not isinstance(bullets, list) or not all(isinstance(b, str) for b in bullets):
        raise ChangesSummaryError("bullets missing or wrong type in response")
    if addressed not in {"yes", "partial", "no", "unclear"}:
        raise ChangesSummaryError(
            f"addressed_feedback must be yes|partial|no|unclear; got {addressed!r}"
        )
    if not isinstance(reason, str):
        reason = ""
    return {
        "summary": summary.strip(),
        "bullets": [b.strip() for b in bullets if b.strip()],
        "addressed_feedback": addressed,
        "addressed_reason": reason.strip(),
    }


__all__ = [
    "ChangesSummary",
    "ChangesSummaryService",
    "ChangesSummaryError",
]
