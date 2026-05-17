"""SQLAlchemy ORM models for the expert console.

Schema overview:

    Session       -- a working context (one env or one task the expert is
                     currently reviewing). Shown in the left sidebar.
    Feedback      -- a single submitted note attached to a session.
    AgentRun      -- a dispatched pipeline invocation. One Feedback may
                     produce zero or one AgentRun (memory-only entries
                     produce zero).
    RunLog        -- a streamed line of output from an AgentRun. The
                     SSE endpoint replays + tails these.
"""

from __future__ import annotations

import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def _uuid() -> str:
    return uuid.uuid4().hex


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ----------------------------------------------------------------------
# Enums
# ----------------------------------------------------------------------


class FeedbackRoute(str, enum.Enum):
    """Which agent the expert wants their note delivered to."""

    AUDIT = "audit"
    CREATOR = "creator"


class MemoryTier(str, enum.Enum):
    """Where the note should be pinned, if at all."""

    GENERAL = "general"
    SPECIFIC = "specific"
    NONE = "none"


class Pipeline(str, enum.Enum):
    """Which underlying driver gets subprocessed."""

    CREATION_AUDIT = "creation_audit"
    PROPOSE_AND_AMPLIFY = "propose_and_amplify"


class RunStatus(str, enum.Enum):
    PENDING = "pending"
    RUNNING = "running"
    FINISHED = "finished"
    FAILED = "failed"
    STOPPED = "stopped"


class SessionStatus(str, enum.Enum):
    ACTIVE = "active"
    ARCHIVED = "archived"


# ----------------------------------------------------------------------
# Tables
# ----------------------------------------------------------------------


class Session(Base):
    """A working context. The left-sidebar "Current Creation" + "Past
    Creations" list is built from these.
    """

    __tablename__ = "sessions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    title: Mapped[str] = mapped_column(String(256))
    env_dir: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    task_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default=SessionStatus.ACTIVE.value, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_now, onupdate=_now
    )

    feedbacks: Mapped[list["Feedback"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", order_by="Feedback.created_at"
    )
    runs: Mapped[list["AgentRun"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", order_by="AgentRun.created_at"
    )


class Feedback(Base):
    """A note submitted by the expert in a session.

    `route` decides which expert_feedback memory file the note is
    appended to (audit vs creator). `memory_tier` controls whether the
    note is GLOBAL or scoped to this env. `suggest_checklist_change`
    routes the note as a proposed audit-checklist amendment in addition
    to (not instead of) the memory append.
    """

    __tablename__ = "feedbacks"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    session_id: Mapped[str] = mapped_column(ForeignKey("sessions.id"), index=True)
    message: Mapped[str] = mapped_column(Text)
    route: Mapped[str] = mapped_column(String(16))  # FeedbackRoute
    memory_tier: Mapped[str] = mapped_column(String(16))  # MemoryTier
    suggest_checklist_change: Mapped[bool] = mapped_column(default=False)
    env_dir: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    task_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_new_task: Mapped[bool] = mapped_column(default=False)
    appended_to_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
    entry_anchor: Mapped[str | None] = mapped_column(String(128), nullable=True)
    dispatched: Mapped[bool] = mapped_column(default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    session: Mapped[Session] = relationship(back_populates="feedbacks")
    run: Mapped["AgentRun | None"] = relationship(back_populates="feedback", uselist=False)


class AgentRun(Base):
    """A dispatched pipeline invocation.

    `command` is the JSON-encoded argv used to subprocess the existing
    driver — useful for debugging / replay. `log_path` points at the
    on-disk newline-delimited log file (we also persist line-by-line
    in `run_logs` for SSE replay).
    """

    __tablename__ = "agent_runs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    session_id: Mapped[str] = mapped_column(ForeignKey("sessions.id"), index=True)
    feedback_id: Mapped[str | None] = mapped_column(
        ForeignKey("feedbacks.id"), index=True, nullable=True
    )
    pipeline: Mapped[str] = mapped_column(String(32))  # Pipeline
    command: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), default=RunStatus.PENDING.value, index=True)
    exit_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    log_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
    pid: Mapped[int | None] = mapped_column(Integer, nullable=True)
    pgid: Mapped[int | None] = mapped_column(Integer, nullable=True)
    current_phase: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    session: Mapped[Session] = relationship(back_populates="runs")
    feedback: Mapped[Feedback | None] = relationship(back_populates="run")
    logs: Mapped[list["RunLog"]] = relationship(
        back_populates="run", cascade="all, delete-orphan", order_by="RunLog.seq"
    )


class RunLog(Base):
    """One line of streamed output. `seq` orders rows within a run,
    cheaper than ORDER BY ts for SSE replay.
    """

    __tablename__ = "run_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    run_id: Mapped[str] = mapped_column(ForeignKey("agent_runs.id"), index=True)
    seq: Mapped[int] = mapped_column(Integer)
    stream: Mapped[str] = mapped_column(String(8))  # stdout | stderr | event
    line: Mapped[str] = mapped_column(Text)
    ts: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)

    run: Mapped[AgentRun] = relationship(back_populates="logs")


__all__ = [
    "FeedbackRoute",
    "MemoryTier",
    "Pipeline",
    "RunStatus",
    "SessionStatus",
    "Session",
    "Feedback",
    "AgentRun",
    "RunLog",
]
