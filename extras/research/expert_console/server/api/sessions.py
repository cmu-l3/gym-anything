"""Session listing and detail endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from ..db import get_db
from ..models import AgentRun, Feedback, Session as SessionRow
from ..schemas.feedback import (
    FeedbackRecord,
    RunSummary,
    SessionDetail,
    SessionSummary,
)


router = APIRouter(prefix="/api/sessions", tags=["sessions"])


@router.get("", response_model=list[SessionSummary])
def list_sessions(
    status: str | None = Query(None, description="active | archived"),
    limit: int = Query(50, ge=1, le=500),
    db=Depends(get_db),
) -> list[SessionSummary]:
    query = db.query(SessionRow).order_by(SessionRow.updated_at.desc())
    if status:
        query = query.filter(SessionRow.status == status)
    rows = query.limit(limit).all()
    return [
        SessionSummary(
            id=row.id,
            title=row.title,
            env_dir=row.env_dir,
            task_id=row.task_id,
            status=row.status,
            created_at=row.created_at,
            updated_at=row.updated_at,
            feedback_count=len(row.feedbacks),
            run_count=len(row.runs),
        )
        for row in rows
    ]


@router.get("/{session_id}", response_model=SessionDetail)
def get_session(session_id: str, db=Depends(get_db)) -> SessionDetail:
    row = db.get(SessionRow, session_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Session not found: {session_id}")
    feedbacks = [
        FeedbackRecord(
            id=f.id,
            message=f.message,
            route=f.route,
            memory_tier=f.memory_tier,
            suggest_checklist_change=f.suggest_checklist_change,
            env_dir=f.env_dir,
            task_id=f.task_id,
            is_new_task=f.is_new_task,
            appended_to_path=f.appended_to_path,
            entry_anchor=f.entry_anchor,
            created_at=f.created_at,
        )
        for f in row.feedbacks
    ]
    runs = [
        RunSummary(
            id=r.id,
            session_id=r.session_id,
            feedback_id=r.feedback_id,
            pipeline=r.pipeline,
            status=r.status,
            current_phase=r.current_phase,
            exit_code=r.exit_code,
            created_at=r.created_at,
            started_at=r.started_at,
            finished_at=r.finished_at,
        )
        for r in row.runs
    ]
    return SessionDetail(
        id=row.id,
        title=row.title,
        env_dir=row.env_dir,
        task_id=row.task_id,
        status=row.status,
        created_at=row.created_at,
        updated_at=row.updated_at,
        feedback_count=len(feedbacks),
        run_count=len(runs),
        feedbacks=feedbacks,
        runs=runs,
    )
