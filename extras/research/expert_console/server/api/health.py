"""Health and configuration introspection endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from ..config import Settings, get_settings


router = APIRouter(prefix="/api", tags=["health"])


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/config")
def config(settings: Settings = Depends(get_settings)) -> dict[str, str]:
    return {
        "repo_root": str(settings.repo_root),
        "environments_dir": str(settings.environments_dir),
        "db_path": str(settings.db_path),
        "summarize_model": settings.summarize_model,
        "summarize_reasoning_effort": settings.summarize_reasoning_effort,
    }
