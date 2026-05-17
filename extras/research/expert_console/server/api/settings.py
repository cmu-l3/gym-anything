"""Settings endpoints — diagnostics (read-only) and preferences (mutable).

Two surfaces:

- `GET /api/settings/diagnostics` — read-only runtime info: repo root,
  config paths, claude binary, key presence flags, version, env stats.
- `GET /api/settings/preferences` — current runtime-mutable knobs.
- `PUT /api/settings/preferences` — update one or more preferences.
- `POST /api/settings/preferences/reset` — restore defaults.
"""

from __future__ import annotations

import os
import shutil
from pathlib import Path

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict

from ..config import Settings, get_settings
from ..services.preferences import (
    Preferences,
    PreferencesError,
    PreferencesService,
)


router = APIRouter(prefix="/api/settings", tags=["settings"])


# ----------------------------------------------------------------------
# Schemas
# ----------------------------------------------------------------------


class DiagnosticsResponse(BaseModel):
    repo_root: str
    environments_dir: str
    creation_audit_memory_dir: str
    propose_amplify_memory_dir: str
    db_path: str
    state_dir: str
    artifacts_dir: str

    backend_host: str
    backend_port: int

    claude_bin: str | None
    npm_bin: str | None
    git_bin: str | None
    openai_api_key_present: bool
    anthropic_api_key_present: bool
    gemini_api_key_present: bool

    env_count: int
    creation_audit_memory_files: int
    propose_amplify_memory_files: int
    expert_feedback_files_present: bool


class PreferencesPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    summarize_model: str | None = None
    summarize_reasoning_effort: str | None = None
    summarize_max_frames: int | None = None
    summarize_max_tokens: int | None = None
    summarize_timeout_sec: int | None = None
    completion_threshold: float | None = None
    integrity_threshold: float | None = None


# ----------------------------------------------------------------------
# Dependencies
# ----------------------------------------------------------------------


def _preferences(request: Request) -> PreferencesService:
    svc: PreferencesService | None = getattr(request.app.state, "preferences", None)
    if svc is None:
        raise HTTPException(
            status_code=500,
            detail="PreferencesService not initialised. This is a server bug.",
        )
    return svc


# ----------------------------------------------------------------------
# Endpoints
# ----------------------------------------------------------------------


@router.get("/diagnostics", response_model=DiagnosticsResponse)
def diagnostics(settings: Settings = Depends(get_settings)) -> DiagnosticsResponse:
    return DiagnosticsResponse(
        repo_root=str(settings.repo_root),
        environments_dir=str(settings.environments_dir),
        creation_audit_memory_dir=str(settings.creation_audit_memory_dir),
        propose_amplify_memory_dir=str(settings.propose_amplify_memory_dir),
        db_path=str(settings.db_path),
        state_dir=str(settings.state_dir),
        artifacts_dir=str(settings.artifacts_dir),
        backend_host=settings.host,
        backend_port=settings.port,
        claude_bin=_resolve_bin(settings.claude_bin, "CLAUDE_BIN", "claude"),
        npm_bin=_resolve_bin(None, "NPM_BIN", "npm"),
        git_bin=_resolve_bin(None, "GIT_BIN", "git"),
        openai_api_key_present=bool(os.environ.get("OPENAI_API_KEY")),
        anthropic_api_key_present=bool(os.environ.get("ANTHROPIC_API_KEY")),
        gemini_api_key_present=bool(os.environ.get("GEMINI_API_KEY")),
        env_count=_count_envs(settings),
        creation_audit_memory_files=_count_md_files(settings.creation_audit_memory_dir),
        propose_amplify_memory_files=_count_md_files(settings.propose_amplify_memory_dir),
        expert_feedback_files_present=all(
            p.is_file()
            for p in (
                settings.expert_feedback_creation_path,
                settings.expert_feedback_audit_path,
                settings.expert_feedback_propose_path,
            )
        ),
    )


@router.get("/preferences", response_model=dict)
def get_preferences(svc: PreferencesService = Depends(_preferences)) -> dict:
    return svc.get().to_dict()


@router.put("/preferences", response_model=dict)
def update_preferences(
    payload: PreferencesPayload,
    svc: PreferencesService = Depends(_preferences),
) -> dict:
    patch = {
        key: value
        for key, value in payload.model_dump(exclude_unset=True).items()
        if value is not None
    }
    if not patch:
        return svc.get().to_dict()
    try:
        return svc.update(patch).to_dict()
    except PreferencesError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.post("/preferences/reset", response_model=dict)
def reset_preferences(svc: PreferencesService = Depends(_preferences)) -> dict:
    return svc.reset().to_dict()


# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------


def _resolve_bin(explicit: str | None, env_var: str, name: str) -> str | None:
    candidate = explicit or os.environ.get(env_var) or shutil.which(name)
    if not candidate:
        return None
    if not Path(candidate).is_file():
        return None
    return str(candidate)


def _count_envs(settings: Settings) -> int:
    if not settings.environments_dir.is_dir():
        return 0
    return sum(
        1
        for p in settings.environments_dir.iterdir()
        if p.is_dir()
        and not p.name.startswith((".", "__"))
        and (p / "env.json").is_file()
    )


def _count_md_files(root: Path) -> int:
    if not root.is_dir():
        return 0
    return sum(1 for _ in root.rglob("*.md"))
