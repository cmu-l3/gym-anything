"""Memory inspection + diff endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from ..config import Settings, get_settings
from ..services.memory import MemoryError, MemoryService
from ..services.memory_diff import (
    EnvDiffService,
    MemoryDiffError,
    MemoryDiffService,
)


router = APIRouter(prefix="/api/memory", tags=["memory"])


def _memory(settings: Settings = Depends(get_settings)) -> MemoryService:
    return MemoryService(settings)


def _diff(settings: Settings = Depends(get_settings)) -> MemoryDiffService:
    return MemoryDiffService(settings)


def _env_diff(settings: Settings = Depends(get_settings)) -> EnvDiffService:
    return EnvDiffService(settings)


@router.get("")
def list_memory(
    env_dir: str | None = Query(None),
    svc: MemoryService = Depends(_memory),
) -> dict:
    try:
        return svc.list_memory(env_dir).to_dict()
    except MemoryError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/file")
def read_file(
    rel_path: str = Query(..., description="Repo-rooted memory file path"),
    svc: MemoryService = Depends(_memory),
) -> dict:
    try:
        text = svc.read_file(rel_path)
    except MemoryError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"rel_path": rel_path, "text": text}


@router.get("/diff")
def get_diff(
    env_dir: str | None = Query(None),
    svc: MemoryDiffService = Depends(_diff),
) -> dict:
    try:
        return svc.get_diff(env_dir).to_dict()
    except MemoryDiffError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@router.get("/diff/env")
def get_env_diff(
    env_dir: str = Query(..., description="Env folder name to diff"),
    svc: EnvDiffService = Depends(_env_diff),
) -> dict:
    """Git diff over the env folder + its audit report.

    Surfaces changes the pipeline made to scripts/, tasks/, config/,
    env.json, README.md, evidence_docs/, and the matching
    audits/audit_<env>.md file.
    """
    try:
        return svc.get_diff(env_dir).to_dict()
    except MemoryDiffError as exc:
        status = 404 if "Unknown env_dir" in str(exc) else 500
        raise HTTPException(status_code=status, detail=str(exc)) from exc
