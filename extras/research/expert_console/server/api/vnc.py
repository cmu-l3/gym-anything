"""VNC lifecycle + WebSocket proxy endpoints."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, WebSocket

from ..services.vnc import VNCError, VNCService


logger = logging.getLogger("expert_console.api.vnc")


router = APIRouter(prefix="/api/vnc", tags=["vnc"])


def _vnc(request: Request) -> VNCService:
    svc: VNCService | None = getattr(request.app.state, "vnc", None)
    if svc is None:
        raise HTTPException(
            status_code=500,
            detail="VNCService not initialised. This is a server bug.",
        )
    return svc


@router.post("/start")
def start(
    payload: dict = Body(...),
    await_ready: bool = Query(
        False,
        description="If true, block until the env finishes booting. "
        "Default false — the env boot can take minutes and would "
        "exceed proxy/browser timeouts. Frontend should poll "
        "GET /api/vnc for status transitions.",
    ),
    svc: VNCService = Depends(_vnc),
) -> dict:
    env_dir = payload.get("env_dir")
    if not isinstance(env_dir, str) or not env_dir:
        raise HTTPException(status_code=400, detail="env_dir is required")
    try:
        session = svc.start(env_dir, await_ready=await_ready)
    except VNCError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return session.to_public()


@router.post("/{session_id}/reset")
def reset(
    session_id: str,
    await_ready: bool = Query(False),
    svc: VNCService = Depends(_vnc),
) -> dict:
    try:
        session = svc.reset(session_id, await_ready=await_ready)
    except VNCError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return session.to_public()


@router.post("/{session_id}/stop")
def stop(session_id: str, svc: VNCService = Depends(_vnc)) -> dict:
    try:
        svc.stop(session_id)
    except VNCError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"stopped": True, "session_id": session_id}


@router.get("")
def current(svc: VNCService = Depends(_vnc)) -> dict:
    s = svc.current()
    if s is None:
        return {"active": False}
    return {"active": True, **s.to_public()}


@router.websocket("/ws/{session_id}")
async def ws(websocket: WebSocket, session_id: str) -> None:
    svc: VNCService = websocket.app.state.vnc
    try:
        # noVNC speaks "binary" subprotocol by default.
        protos = websocket.scope.get("subprotocols") or []
        accept_proto = "binary" if "binary" in protos else None
        await websocket.accept(subprotocol=accept_proto)
    except Exception:
        return
    try:
        await svc.proxy(session_id, websocket)
    except VNCError as exc:
        logger.warning("VNC proxy error: %s", exc)
