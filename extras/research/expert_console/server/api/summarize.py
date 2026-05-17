"""Summarization endpoint — turn an artifact path into plain English."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from ..config import Settings, get_settings
from ..services.inspection import InspectionError, InspectionService
from ..services.preferences import PreferencesService
from ..services.summarize import (
    SummarizationError,
    SummarizationService,
    SummaryKind,
    kind_from_artifact,
)


logger = logging.getLogger("expert_console.api.summarize")

router = APIRouter(prefix="/api/summarize", tags=["summarize"])


class SummarizeRequest(BaseModel):
    rel_path: str = Field(..., description="Repo-rooted artifact path.")
    artifact_role: str | None = Field(
        None,
        description="Role label from the inspection service (e.g. 'verifier'). "
        "Used to pick the summarization prompt.",
    )
    kind_hint: str | None = Field(
        None,
        description="ArtifactKind value from the inspection service.",
    )
    force: bool = Field(False, description="Bypass the cache.")


def _inspection(settings: Settings = Depends(get_settings)) -> InspectionService:
    return InspectionService(settings)


def _summarizer(
    request: Request, settings: Settings = Depends(get_settings)
) -> SummarizationService:
    prefs: PreferencesService | None = getattr(request.app.state, "preferences", None)
    return SummarizationService(settings, preferences=prefs)


@router.post("")
def summarize(
    request: SummarizeRequest = Body(...),
    inspection: InspectionService = Depends(_inspection),
    summarizer: SummarizationService = Depends(_summarizer),
) -> dict:
    try:
        content = inspection.get_artifact_content(request.rel_path)
    except InspectionError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    if content.text is None:
        raise HTTPException(
            status_code=415,
            detail=(
                f"Artifact at {content.rel_path} is not summarizable text "
                f"(kind={content.kind.value})."
            ),
        )
    kind = kind_from_artifact(
        name=content.rel_path.split("/")[-1],
        role=request.artifact_role,
        kind_hint=request.kind_hint or content.kind.value,
    )
    label = f"{request.rel_path} (role={request.artifact_role or 'unknown'})"
    try:
        result = summarizer.summarize_text(
            content=content.text,
            kind=kind,
            artifact_label=label,
            force=request.force,
        )
    except SummarizationError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {
        "rel_path": content.rel_path,
        "kind": kind.value,
        "truncated": content.truncated,
        "result": result.to_dict(),
    }
