"""Pipeline dispatch service.

Submitting a feedback always:
  1. Resolves which pipeline to drive (creation_audit vs propose_and_amplify).
  2. Appends the note to the right `expert_feedback.md` so the pipeline's
     prompt picks it up (the prompts already reference these files —
     see Stage 1).
  3. If a target env was picked, launches the **existing** driver as a
     subprocess (we do NOT reimplement the pipeline) with stdout/stderr
     streamed line-by-line into `RunLog` rows so the SSE endpoint can
     tail them.

Routing:

    target              | pipeline               | invocation
    --------------------+------------------------+-------------------------------
    env, no task        | creation_audit         | python -m ...creation_audit.method
                        |                        |   --start-idx 1 (skip initial; the
                        |                        |   env already exists, the new
                        |                        |   feedback is in expert_feedback.md
                        |                        |   so the nudge + audit pick it up)
    env, audit route    | creation_audit         | same as above but blind_nudges=0
                        |                        |   so only audit rounds run.
    env + task          | propose_and_amplify    | --stage propose --env-dir <env>
    env + new task      | propose_and_amplify    | --stage all --env-dir <env>
                        |                        |   (full propose + amplify + extract)
    no env              | none                   | memory append only, no dispatch
"""

from __future__ import annotations

import enum
import json
import logging
import os
import re
import shlex
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from sqlalchemy.orm import sessionmaker

from ..config import Settings
from ..db import get_sessionmaker
from ..models import (
    AgentRun,
    Feedback,
    FeedbackRoute,
    MemoryTier as MemoryTierEnum,
    Pipeline as PipelineEnum,
    RunLog,
    RunStatus,
    Session as SessionRow,
    SessionStatus,
)
from .memory import (
    EntryRecord,
    FeedbackTarget,
    MemoryError,
    MemoryService,
    MemoryTier,
)


logger = logging.getLogger("expert_console.dispatch")


# ----------------------------------------------------------------------
# Types
# ----------------------------------------------------------------------


class DispatchError(RuntimeError):
    """Raised when the requested dispatch is invalid."""


@dataclass
class FeedbackPayload:
    session_id: str | None
    message: str
    route: FeedbackRoute
    memory_tier: MemoryTier
    suggest_checklist_change: bool
    env_dir: str | None
    task_id: str | None
    is_new_task: bool


@dataclass
class SubmitResult:
    feedback_id: str
    session_id: str
    memory_entry: EntryRecord
    run_id: str | None
    pipeline: PipelineEnum | None
    command: list[str] | None
    dispatched: bool


# ----------------------------------------------------------------------
# Run handle (process registry)
# ----------------------------------------------------------------------


@dataclass
class _RunHandle:
    run_id: str
    proc: subprocess.Popen
    pgid: int
    log_path: Path
    thread: threading.Thread
    started_at: float


# ----------------------------------------------------------------------
# Dispatch service
# ----------------------------------------------------------------------


_PHASE_RE = re.compile(r"=== ([\w-]+ [\w\d ]+?) ===")


class DispatchService:
    """Orchestrates feedback persistence, memory append, and subprocess
    launch. One instance per process — owns the run registry.
    """

    def __init__(
        self,
        settings: Settings,
        *,
        memory_service: MemoryService | None = None,
        session_factory: sessionmaker | None = None,
        subprocess_launcher: "SubprocessLauncher | None" = None,
    ) -> None:
        self.settings = settings
        self.memory = memory_service or MemoryService(settings)
        self._sessionmaker = session_factory or get_sessionmaker()
        self._launcher = subprocess_launcher or RealSubprocessLauncher()
        self._runs: dict[str, _RunHandle] = {}
        self._runs_lock = threading.Lock()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def submit(self, payload: FeedbackPayload) -> SubmitResult:
        self._validate(payload)

        target = self._target_for(payload)

        entry = self.memory.append_expert_entry(
            target=target,
            memory_tier=payload.memory_tier,
            env_dir=payload.env_dir,
            task_id=payload.task_id,
            body=payload.message.strip(),
            suggest_checklist_change=payload.suggest_checklist_change,
        )

        session_id = self._ensure_session(payload)
        feedback_id = self._record_feedback(session_id, payload, entry)

        if payload.env_dir is None:
            return SubmitResult(
                feedback_id=feedback_id,
                session_id=session_id,
                memory_entry=entry,
                run_id=None,
                pipeline=None,
                command=None,
                dispatched=False,
            )

        pipeline, command = self._build_command(payload)
        run_id = self._launch(
            session_id=session_id,
            feedback_id=feedback_id,
            pipeline=pipeline,
            command=command,
        )
        return SubmitResult(
            feedback_id=feedback_id,
            session_id=session_id,
            memory_entry=entry,
            run_id=run_id,
            pipeline=pipeline,
            command=command,
            dispatched=True,
        )

    def stop_run(self, run_id: str) -> bool:
        with self._runs_lock:
            handle = self._runs.get(run_id)
        if handle is None:
            return False
        try:
            os.killpg(handle.pgid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        return True

    def get_run(self, run_id: str) -> AgentRun:
        with self._sessionmaker() as db:
            run = db.get(AgentRun, run_id)
            if run is None:
                raise DispatchError(f"Run not found: {run_id}")
            db.expunge(run)
            return run

    def list_runs(
        self, *, session_id: str | None = None, limit: int = 50
    ) -> list[AgentRun]:
        with self._sessionmaker() as db:
            query = db.query(AgentRun).order_by(AgentRun.created_at.desc())
            if session_id is not None:
                query = query.filter(AgentRun.session_id == session_id)
            rows = query.limit(limit).all()
            for r in rows:
                db.expunge(r)
            return rows

    def fetch_logs(
        self, run_id: str, *, after_seq: int = -1, limit: int = 500
    ) -> list[RunLog]:
        with self._sessionmaker() as db:
            rows = (
                db.query(RunLog)
                .filter(RunLog.run_id == run_id, RunLog.seq > after_seq)
                .order_by(RunLog.seq)
                .limit(limit)
                .all()
            )
            for row in rows:
                db.expunge(row)
            return rows

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _validate(self, p: FeedbackPayload) -> None:
        if not p.message or not p.message.strip():
            raise DispatchError("Feedback message must not be empty.")
        if p.env_dir is None:
            if p.task_id is not None or p.is_new_task:
                raise DispatchError(
                    "task_id / is_new_task require env_dir to be set."
                )
            if p.memory_tier is MemoryTier.SPECIFIC:
                raise DispatchError(
                    "memory_tier=SPECIFIC requires env_dir to be set."
                )
        else:
            env_path = self.settings.environments_dir / p.env_dir
            if not env_path.is_dir():
                raise DispatchError(f"Unknown env_dir: {p.env_dir}")
            if p.task_id is not None and not p.is_new_task:
                task_path = env_path / "tasks" / p.task_id
                if not task_path.is_dir():
                    raise DispatchError(
                        f"Unknown task: {p.env_dir}/{p.task_id}"
                    )

    def _target_for(self, p: FeedbackPayload) -> FeedbackTarget:
        if p.task_id is not None or p.is_new_task:
            return FeedbackTarget.PROPOSER
        if p.route is FeedbackRoute.AUDIT:
            return FeedbackTarget.AUDIT
        return FeedbackTarget.CREATOR


    def _ensure_session(self, p: FeedbackPayload) -> str:
        with self._sessionmaker() as db:
            if p.session_id:
                sess = db.get(SessionRow, p.session_id)
                if sess is None:
                    raise DispatchError(f"Session not found: {p.session_id}")
                sess.updated_at = datetime.now(timezone.utc)
                # Update binding if the expert switched target inside a session.
                if p.env_dir is not None:
                    sess.env_dir = p.env_dir
                if p.task_id is not None:
                    sess.task_id = p.task_id
                db.commit()
                return sess.id
            title = self._derive_session_title(p)
            sess = SessionRow(
                title=title,
                env_dir=p.env_dir,
                task_id=p.task_id,
                status=SessionStatus.ACTIVE.value,
            )
            db.add(sess)
            db.commit()
            return sess.id

    def _derive_session_title(self, p: FeedbackPayload) -> str:
        if p.env_dir and p.task_id:
            return f"{p.env_dir} / {p.task_id}"
        if p.env_dir:
            return p.env_dir
        return "general feedback"

    def _record_feedback(
        self, session_id: str, p: FeedbackPayload, entry: EntryRecord
    ) -> str:
        with self._sessionmaker() as db:
            fb = Feedback(
                session_id=session_id,
                message=p.message.strip(),
                route=p.route.value,
                memory_tier=(
                    MemoryTierEnum.GENERAL.value
                    if p.memory_tier is MemoryTier.GENERAL
                    else MemoryTierEnum.SPECIFIC.value
                ),
                suggest_checklist_change=p.suggest_checklist_change,
                env_dir=p.env_dir,
                task_id=p.task_id,
                is_new_task=p.is_new_task,
                appended_to_path=entry.rel_path,
                entry_anchor=entry.anchor,
                dispatched=False,
            )
            db.add(fb)
            db.commit()
            return fb.id

    # ------------------------------------------------------------------
    # Command construction
    # ------------------------------------------------------------------

    def _build_command(
        self, p: FeedbackPayload
    ) -> tuple[PipelineEnum, list[str]]:
        """Pick the right pipeline driver for the feedback target.

        Routing matrix:
          env     task    new_task  route    -> driver
          ------  ------  --------  -------  ----------------------------
          set    set     False     n/a      edit_task    (edit one task)
          set    -       True      n/a      propose_and_amplify --stage all
                                            (create one new task end-to-end)
          set    -       False     creator  edit_env     (edit env scripts)
          set    -       False     audit    edit_env --route audit
          -      -       -         -        memory append only, no dispatch
        """
        if p.is_new_task:
            return (
                PipelineEnum.PROPOSE_AND_AMPLIFY,
                self._new_task_cmd(p),
            )
        if p.task_id is not None:
            return (
                PipelineEnum.PROPOSE_AND_AMPLIFY,
                self._edit_task_cmd(p),
            )
        return PipelineEnum.CREATION_AUDIT, self._edit_env_cmd(p)

    def _edit_env_cmd(self, p: FeedbackPayload) -> list[str]:
        """Refactor an existing env in place per expert feedback."""
        return [
            sys.executable,
            "-m",
            "extras.research.software_as_env.creation_audit.edit_env",
            p.env_dir,
            "--route",
            "audit" if p.route is FeedbackRoute.AUDIT else "creator",
        ]

    def _edit_task_cmd(self, p: FeedbackPayload) -> list[str]:
        """Refactor an existing task in place per expert feedback."""
        software = self._derive_software_name(p.env_dir)
        return [
            sys.executable,
            "-m",
            "extras.research.task_generation.propose_and_amplify.method",
            "--software",
            software,
            "--env-dir",
            p.env_dir,
            "--stage",
            "edit",
            "--target-task",
            p.task_id,
        ]

    def _new_task_cmd(self, p: FeedbackPayload) -> list[str]:
        """Generate one (or more) brand-new tasks for an existing env."""
        software = self._derive_software_name(p.env_dir)
        return [
            sys.executable,
            "-m",
            "extras.research.task_generation.propose_and_amplify.method",
            "--software",
            software,
            "--env-dir",
            p.env_dir,
            "--stage",
            "all",
        ]

    def _derive_software_name(self, env_dir: str) -> str:
        env_json = self.settings.environments_dir / env_dir / "env.json"
        if env_json.is_file():
            try:
                spec = json.loads(env_json.read_text(encoding="utf-8"))
                desc = spec.get("description")
                if isinstance(desc, str):
                    first = desc.split(".")[0].split(" environment")[0]
                    if 2 <= len(first) <= 80:
                        return first.strip()
            except (OSError, json.JSONDecodeError):
                pass
        base = env_dir.removesuffix("_env").replace("_", " ").strip()
        return base.title() if base else env_dir

    # ------------------------------------------------------------------
    # Subprocess launch
    # ------------------------------------------------------------------

    def _launch(
        self,
        *,
        session_id: str,
        feedback_id: str,
        pipeline: PipelineEnum,
        command: list[str],
    ) -> str:
        with self._sessionmaker() as db:
            run = AgentRun(
                session_id=session_id,
                feedback_id=feedback_id,
                pipeline=pipeline.value,
                command=json.dumps(command),
                status=RunStatus.PENDING.value,
            )
            db.add(run)
            db.commit()
            run_id = run.id

        log_path = self.settings.artifacts_dir / f"{run_id}.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            proc, pgid = self._launcher.start(
                command,
                cwd=self.settings.repo_root,
            )
        except Exception as exc:
            self._mark_failed(run_id, exit_code=None, message=str(exc))
            raise DispatchError(
                f"Failed to launch pipeline subprocess: {exc}"
            ) from exc

        with self._sessionmaker() as db:
            run = db.get(AgentRun, run_id)
            if run is not None:
                run.pid = proc.pid
                run.pgid = pgid
                run.log_path = str(log_path)
                run.status = RunStatus.RUNNING.value
                run.started_at = datetime.now(timezone.utc)
                db.commit()

        thread = threading.Thread(
            target=self._stream,
            args=(run_id, proc, log_path),
            daemon=True,
            name=f"dispatch-stream-{run_id}",
        )

        with self._runs_lock:
            self._runs[run_id] = _RunHandle(
                run_id=run_id,
                proc=proc,
                pgid=pgid,
                log_path=log_path,
                thread=thread,
                started_at=time.time(),
            )

        thread.start()
        return run_id

    def _stream(
        self, run_id: str, proc: subprocess.Popen, log_path: Path
    ) -> None:
        seq = 0
        try:
            with log_path.open("w", encoding="utf-8") as logf:
                assert proc.stdout is not None  # we always pipe
                for raw in proc.stdout:
                    line = raw.rstrip("\n")
                    logf.write(line + "\n")
                    logf.flush()
                    self._persist_log(run_id, seq, "stdout", line)
                    self._maybe_update_phase(run_id, line)
                    seq += 1
            proc.wait()
        except Exception as exc:
            logger.exception("Dispatch stream error for run %s", run_id)
            self._persist_log(run_id, seq, "event", f"stream-error: {exc}")
        finally:
            exit_code = proc.returncode
            self._finalize(run_id, exit_code)
            with self._runs_lock:
                self._runs.pop(run_id, None)

    def _persist_log(self, run_id: str, seq: int, stream: str, line: str) -> None:
        with self._sessionmaker() as db:
            db.add(
                RunLog(
                    run_id=run_id,
                    seq=seq,
                    stream=stream,
                    line=line,
                )
            )
            db.commit()

    def _maybe_update_phase(self, run_id: str, line: str) -> None:
        match = _PHASE_RE.search(line)
        if not match:
            return
        phase = match.group(1).strip()
        with self._sessionmaker() as db:
            run = db.get(AgentRun, run_id)
            if run is None:
                return
            run.current_phase = phase
            db.commit()

    def _mark_failed(
        self, run_id: str, *, exit_code: int | None, message: str
    ) -> None:
        with self._sessionmaker() as db:
            run = db.get(AgentRun, run_id)
            if run is None:
                return
            run.status = RunStatus.FAILED.value
            run.exit_code = exit_code
            run.finished_at = datetime.now(timezone.utc)
            db.add(
                RunLog(
                    run_id=run_id,
                    seq=10**9,  # sentinel high seq for failure marker
                    stream="event",
                    line=f"launch-failure: {message}",
                )
            )
            db.commit()

    def _finalize(self, run_id: str, exit_code: int | None) -> None:
        with self._sessionmaker() as db:
            run = db.get(AgentRun, run_id)
            if run is None:
                return
            run.exit_code = exit_code
            run.finished_at = datetime.now(timezone.utc)
            if exit_code == 0:
                run.status = RunStatus.FINISHED.value
            elif exit_code is None or exit_code < 0:
                run.status = RunStatus.STOPPED.value
            else:
                run.status = RunStatus.FAILED.value
            db.commit()


# ----------------------------------------------------------------------
# Subprocess launcher (extracted so tests can stub)
# ----------------------------------------------------------------------


class SubprocessLauncher:
    def start(
        self, command: list[str], *, cwd: Path
    ) -> tuple[subprocess.Popen, int]:  # pragma: no cover (covered by stub)
        raise NotImplementedError


class RealSubprocessLauncher(SubprocessLauncher):
    def start(
        self, command: list[str], *, cwd: Path
    ) -> tuple[subprocess.Popen, int]:
        proc = subprocess.Popen(
            command,
            cwd=str(cwd),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        pgid = os.getpgid(proc.pid)
        logger.info(
            "Launched pipeline pid=%s pgid=%s cmd=%s",
            proc.pid,
            pgid,
            shlex.join(command),
        )
        return proc, pgid


__all__ = [
    "DispatchService",
    "DispatchError",
    "FeedbackPayload",
    "SubmitResult",
    "SubprocessLauncher",
    "RealSubprocessLauncher",
]
