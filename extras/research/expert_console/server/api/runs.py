"""Agent-run inspection, SSE log stream, and stop endpoint."""

from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sse_starlette.sse import EventSourceResponse

from ..config import Settings, get_settings
from ..models import RunStatus
from ..schemas.feedback import RunDetail, RunLogEntry, RunSummary
from ..services.changes_summary import (
    ChangesSummaryError,
    ChangesSummaryService,
)
from ..services.dispatch import DispatchError, DispatchService
from ..services.preferences import PreferencesService


logger = logging.getLogger("expert_console.api.runs")

router = APIRouter(prefix="/api/runs", tags=["runs"])


def _dispatcher(request: Request) -> DispatchService:
    svc: DispatchService | None = getattr(request.app.state, "dispatcher", None)
    if svc is None:
        raise HTTPException(
            status_code=500,
            detail="DispatchService not initialised. This is a server bug.",
        )
    return svc


_TERMINAL_STATES = {
    RunStatus.FINISHED.value,
    RunStatus.FAILED.value,
    RunStatus.STOPPED.value,
}


@router.get("", response_model=list[RunSummary])
def list_runs(
    session_id: str | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    dispatcher: DispatchService = Depends(_dispatcher),
) -> list[RunSummary]:
    rows = dispatcher.list_runs(session_id=session_id, limit=limit)
    return [_row_to_summary(r) for r in rows]


@router.get("/{run_id}", response_model=RunDetail)
def get_run(
    run_id: str,
    dispatcher: DispatchService = Depends(_dispatcher),
) -> RunDetail:
    try:
        row = dispatcher.get_run(run_id)
    except DispatchError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    logs = [
        RunLogEntry(seq=log.seq, stream=log.stream, line=log.line, ts=log.ts)
        for log in dispatcher.fetch_logs(run_id, after_seq=-1, limit=10_000)
    ]
    try:
        command = json.loads(row.command)
    except (TypeError, json.JSONDecodeError):
        command = []
    return RunDetail(
        id=row.id,
        session_id=row.session_id,
        feedback_id=row.feedback_id,
        pipeline=row.pipeline,
        status=row.status,
        current_phase=row.current_phase,
        exit_code=row.exit_code,
        created_at=row.created_at,
        started_at=row.started_at,
        finished_at=row.finished_at,
        command=command,
        logs=logs,
    )


@router.post("/{run_id}/stop")
def stop_run(
    run_id: str,
    dispatcher: DispatchService = Depends(_dispatcher),
) -> dict:
    if not dispatcher.stop_run(run_id):
        raise HTTPException(
            status_code=404,
            detail=f"Run not found or already finished: {run_id}",
        )
    return {"stopped": True, "run_id": run_id}


def _changes_summary_service(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> ChangesSummaryService:
    prefs: PreferencesService | None = getattr(
        request.app.state, "preferences", None
    )
    return ChangesSummaryService(settings, preferences=prefs)


@router.get("/{run_id}/changes-summary")
def changes_summary(
    run_id: str,
    force: bool = Query(False, description="Bypass cache"),
    svc: ChangesSummaryService = Depends(_changes_summary_service),
) -> dict:
    """Plain-English summary of what this run changed inside the env,
    plus an explicit judgment of whether the originating expert
    feedback was addressed.

    Results are cached by (run_id, diff signature, model, effort) so
    re-opening a finished run is free.
    """
    try:
        return svc.summarize(run_id, force=force).to_dict()
    except ChangesSummaryError as exc:
        status = 404 if "Run not found" in str(exc) else 502
        raise HTTPException(status_code=status, detail=str(exc)) from exc


@router.get("/{run_id}/stream")
async def stream_run(
    run_id: str,
    request: Request,
    dispatcher: DispatchService = Depends(_dispatcher),
):
    """Server-Sent Events stream of run logs + final-state event.

    The frontend opens this immediately after POST /api/feedback returns
    a run_id. Replays existing logs (sorted by seq) then tails new ones
    by polling at 250ms intervals. Closes on terminal status.
    """
    try:
        run = dispatcher.get_run(run_id)
    except DispatchError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    async def _events():
        last_seq = -1
        while True:
            if await request.is_disconnected():
                break
            logs = dispatcher.fetch_logs(run_id, after_seq=last_seq, limit=500)
            for log in logs:
                yield {
                    "event": "log",
                    "data": json.dumps(
                        {
                            "seq": log.seq,
                            "stream": log.stream,
                            "line": log.line,
                            "ts": log.ts.isoformat(),
                        }
                    ),
                }
                last_seq = max(last_seq, log.seq)
            current = dispatcher.get_run(run_id)
            if current.status in _TERMINAL_STATES:
                yield {
                    "event": "status",
                    "data": json.dumps(
                        {
                            "status": current.status,
                            "exit_code": current.exit_code,
                            "current_phase": current.current_phase,
                        }
                    ),
                }
                break
            yield {
                "event": "status",
                "data": json.dumps(
                    {
                        "status": current.status,
                        "exit_code": current.exit_code,
                        "current_phase": current.current_phase,
                    }
                ),
            }
            await asyncio.sleep(0.25)

    return EventSourceResponse(_events())


def _row_to_summary(row) -> RunSummary:
    return RunSummary(
        id=row.id,
        session_id=row.session_id,
        feedback_id=row.feedback_id,
        pipeline=row.pipeline,
        status=row.status,
        current_phase=row.current_phase,
        exit_code=row.exit_code,
        created_at=row.created_at,
        started_at=row.started_at,
        finished_at=row.finished_at,
    )
