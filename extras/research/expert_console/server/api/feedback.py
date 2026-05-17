"""POST /api/feedback — submit an expert note, optionally dispatch."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Request

from ..config import Settings, get_settings
from ..schemas.feedback import (
    FeedbackResponse,
    FeedbackSubmission,
    MemoryEntryResponse,
)
from ..services.dispatch import DispatchError, DispatchService, FeedbackPayload
from ..services.memory import MemoryTier
from ..models import FeedbackRoute


logger = logging.getLogger("expert_console.api.feedback")


router = APIRouter(prefix="/api/feedback", tags=["feedback"])


def _dispatcher(request: Request) -> DispatchService:
    svc: DispatchService | None = getattr(request.app.state, "dispatcher", None)
    if svc is None:
        raise HTTPException(
            status_code=500,
            detail="DispatchService not initialised. This is a server bug.",
        )
    return svc


@router.post("", response_model=FeedbackResponse)
def submit_feedback(
    submission: FeedbackSubmission,
    dispatcher: DispatchService = Depends(_dispatcher),
) -> FeedbackResponse:
    payload = FeedbackPayload(
        session_id=submission.session_id,
        message=submission.message,
        route=FeedbackRoute(submission.route),
        memory_tier=MemoryTier(submission.memory_tier),
        suggest_checklist_change=submission.suggest_checklist_change,
        env_dir=submission.env_dir,
        task_id=submission.task_id,
        is_new_task=submission.is_new_task,
    )
    try:
        result = dispatcher.submit(payload)
    except DispatchError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return FeedbackResponse(
        feedback_id=result.feedback_id,
        session_id=result.session_id,
        memory_entry=MemoryEntryResponse(
            rel_path=result.memory_entry.rel_path,
            anchor=result.memory_entry.anchor,
            timestamp=result.memory_entry.timestamp,
        ),
        run_id=result.run_id,
        pipeline=result.pipeline.value if result.pipeline else None,
        command=result.command,
        dispatched=result.dispatched,
    )
