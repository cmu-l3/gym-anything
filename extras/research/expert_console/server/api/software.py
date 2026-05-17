"""Software inspection endpoints — env list, task list, env/task views,
and raw artifact preview.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from ..config import Settings, get_settings
from ..services.inspection import InspectionError, InspectionService


router = APIRouter(prefix="/api/software", tags=["software"])


def _service(settings: Settings = Depends(get_settings)) -> InspectionService:
    return InspectionService(settings)


@router.get("")
def list_software(svc: InspectionService = Depends(_service)) -> dict:
    entries = svc.list_software()
    return {"items": [e.to_dict() for e in entries], "count": len(entries)}


@router.get("/{env_dir}")
def get_env(env_dir: str, svc: InspectionService = Depends(_service)) -> dict:
    try:
        return svc.get_env_view(env_dir).to_dict()
    except InspectionError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/{env_dir}/tasks")
def list_tasks(env_dir: str, svc: InspectionService = Depends(_service)) -> dict:
    try:
        items = svc.list_tasks(env_dir)
    except InspectionError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"items": [t.to_dict() for t in items], "count": len(items)}


@router.get("/{env_dir}/tasks/{task_id}")
def get_task(env_dir: str, task_id: str, svc: InspectionService = Depends(_service)) -> dict:
    try:
        return svc.get_task_view(env_dir, task_id).to_dict()
    except InspectionError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/{env_dir}/artifact")
def get_artifact(
    env_dir: str,
    rel_path: str,
    svc: InspectionService = Depends(_service),
) -> dict:
    """Return the raw text content of an artifact, capped to a preview
    window. `env_dir` is in the URL only for breadcrumbing — the
    canonical address is the `rel_path` query arg (relative to repo
    root).
    """
    if not rel_path:
        raise HTTPException(status_code=400, detail="rel_path is required")
    if env_dir not in rel_path:
        raise HTTPException(
            status_code=400,
            detail=f"rel_path must reference env_dir={env_dir}",
        )
    try:
        return svc.get_artifact_content(rel_path).to_dict()
    except InspectionError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
