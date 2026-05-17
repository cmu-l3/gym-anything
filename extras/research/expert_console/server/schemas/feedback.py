"""Pydantic schemas for the feedback / session / run APIs."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


# ----------------------------------------------------------------------
# Submission
# ----------------------------------------------------------------------


class FeedbackSubmission(BaseModel):
    """Body of POST /api/feedback.

    The UI carries the selected target (env_dir / task_id) as part of
    the picker chip below the input. Routing is derived from those plus
    the route + memory_tier toggles.
    """

    session_id: str | None = Field(
        None,
        description="Continue an existing session, or omit to create one.",
    )
    message: str = Field(..., min_length=1, max_length=8000)
    route: Literal["audit", "creator"] = Field(
        "creator",
        description="Which agent the feedback goes to (only meaningful "
        "for env-level dispatches; task-level always goes to proposer).",
    )
    memory_tier: Literal["general", "specific"] = Field(
        "general",
        description="GLOBAL vs env-specific scope for the memory entry.",
    )
    suggest_checklist_change: bool = Field(
        False,
        description="Flag the note as a proposed audit-checklist amendment.",
    )
    env_dir: str | None = Field(
        None,
        description="Target env folder. Null = memory append only, no dispatch.",
    )
    task_id: str | None = Field(
        None,
        description="Existing task to edit. Triggers propose-only dispatch.",
    )
    is_new_task: bool = Field(
        False,
        description="If true, dispatch the full propose-and-amplify for a "
        "single new task. Ignored unless env_dir is set.",
    )


class MemoryEntryResponse(BaseModel):
    rel_path: str
    anchor: str
    timestamp: str


class FeedbackResponse(BaseModel):
    feedback_id: str
    session_id: str
    memory_entry: MemoryEntryResponse
    run_id: str | None
    pipeline: str | None
    command: list[str] | None
    dispatched: bool


# ----------------------------------------------------------------------
# Sessions
# ----------------------------------------------------------------------


class SessionSummary(BaseModel):
    id: str
    title: str
    env_dir: str | None
    task_id: str | None
    status: str
    created_at: datetime
    updated_at: datetime
    feedback_count: int = 0
    run_count: int = 0


class SessionDetail(SessionSummary):
    feedbacks: list["FeedbackRecord"]
    runs: list["RunSummary"]


class FeedbackRecord(BaseModel):
    id: str
    message: str
    route: str
    memory_tier: str
    suggest_checklist_change: bool
    env_dir: str | None
    task_id: str | None
    is_new_task: bool
    appended_to_path: str | None
    entry_anchor: str | None
    created_at: datetime


# ----------------------------------------------------------------------
# Runs
# ----------------------------------------------------------------------


class RunSummary(BaseModel):
    id: str
    session_id: str
    feedback_id: str | None
    pipeline: str
    status: str
    current_phase: str | None
    exit_code: int | None
    created_at: datetime
    started_at: datetime | None
    finished_at: datetime | None


class RunLogEntry(BaseModel):
    seq: int
    stream: str
    line: str
    ts: datetime


class RunDetail(RunSummary):
    command: list[str]
    logs: list[RunLogEntry]


SessionDetail.model_rebuild()
