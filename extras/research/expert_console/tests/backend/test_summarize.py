"""Tests for the summarization service.

The real OpenAI backend is replaced with a stub that records its
inputs and returns canned JSON, so tests don't make network calls.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.services.summarize import (
    OpenAIBackend,
    SummarizationError,
    SummarizationService,
    SummaryKind,
    kind_from_artifact,
)


# ----------------------------------------------------------------------
# Stub backend
# ----------------------------------------------------------------------


class _StubBackend:
    def __init__(self, responses: list[str] | None = None) -> None:
        self.calls: list[dict[str, Any]] = []
        self.responses = list(responses or [])

    def respond(
        self,
        *,
        model: str,
        reasoning_effort: str,
        system: str,
        user: str,
        timeout: float,
    ) -> str:
        self.calls.append(
            {
                "model": model,
                "reasoning_effort": reasoning_effort,
                "system": system,
                "user": user,
                "timeout": timeout,
            }
        )
        if self.responses:
            return self.responses.pop(0)
        return json.dumps(
            {
                "summary": "This script installs Moodle, configures MariaDB, and sets up an admin account.",
                "bullets": [
                    "Installs Moodle via apt",
                    "Creates a MariaDB database",
                    "Seeds an admin user",
                ],
            }
        )


# ----------------------------------------------------------------------
# kind_from_artifact
# ----------------------------------------------------------------------


@pytest.mark.parametrize(
    "name,role,kind_hint,expected",
    [
        ("verifier.py", "verifier", "python", SummaryKind.VERIFIER),
        ("vlm_checklist.json", "vlm_checklist", "json", SummaryKind.VLM_CHECKLIST),
        ("task.json", "task_spec", "json", SummaryKind.TASK_SPEC),
        ("env.json", "env_spec", "json", SummaryKind.ENV_SPEC),
        ("install_moodle.sh", "install_script", "shell", SummaryKind.SCRIPT),
        ("audit_moodle_env.md", None, "markdown", SummaryKind.AUDIT),
        ("README.md", "readme", "markdown", SummaryKind.GENERIC),
    ],
)
def test_kind_from_artifact(name, role, kind_hint, expected) -> None:
    assert kind_from_artifact(name, role, kind_hint) is expected


# ----------------------------------------------------------------------
# Summarization service
# ----------------------------------------------------------------------


def test_summarize_round_trips_through_stub(test_settings: Settings) -> None:
    stub = _StubBackend()
    svc = SummarizationService(test_settings, backend=stub)
    result = svc.summarize_text(
        content="#!/bin/bash\napt install moodle",
        kind=SummaryKind.SCRIPT,
        artifact_label="install_moodle.sh",
    )
    assert "Moodle" in result.summary
    assert len(result.bullets) >= 1
    assert result.cached is False
    assert result.model == test_settings.summarize_model
    assert result.reasoning_effort == test_settings.summarize_reasoning_effort
    assert len(stub.calls) == 1
    call = stub.calls[0]
    assert call["reasoning_effort"] == "medium"
    assert "install_moodle.sh" in call["user"]


def test_summarize_cache_hit(test_settings: Settings) -> None:
    stub = _StubBackend()
    svc = SummarizationService(test_settings, backend=stub)
    first = svc.summarize_text(
        content="echo hello",
        kind=SummaryKind.SCRIPT,
        artifact_label="x.sh",
    )
    assert first.cached is False
    second = svc.summarize_text(
        content="echo hello",
        kind=SummaryKind.SCRIPT,
        artifact_label="x.sh",
    )
    assert second.cached is True
    assert second.summary == first.summary
    assert len(stub.calls) == 1  # second call hit the cache


def test_summarize_force_bypasses_cache(test_settings: Settings) -> None:
    stub = _StubBackend()
    svc = SummarizationService(test_settings, backend=stub)
    svc.summarize_text(
        content="echo hello",
        kind=SummaryKind.SCRIPT,
        artifact_label="x.sh",
    )
    svc.summarize_text(
        content="echo hello",
        kind=SummaryKind.SCRIPT,
        artifact_label="x.sh",
        force=True,
    )
    assert len(stub.calls) == 2


def test_summarize_fails_loud_on_empty_content(test_settings: Settings) -> None:
    svc = SummarizationService(test_settings, backend=_StubBackend())
    with pytest.raises(SummarizationError):
        svc.summarize_text(content="   ", kind=SummaryKind.SCRIPT, artifact_label="x")


def test_summarize_fails_loud_on_invalid_json(test_settings: Settings) -> None:
    stub = _StubBackend(responses=["this is not JSON"])
    svc = SummarizationService(test_settings, backend=stub)
    with pytest.raises(SummarizationError):
        svc.summarize_text(
            content="echo hi", kind=SummaryKind.SCRIPT, artifact_label="x"
        )


def test_summarize_strips_code_fences(test_settings: Settings) -> None:
    stub = _StubBackend(
        responses=[
            "```json\n"
            + json.dumps({"summary": "Ok.", "bullets": ["bullet"]})
            + "\n```"
        ]
    )
    svc = SummarizationService(test_settings, backend=stub)
    result = svc.summarize_text(
        content="echo hi", kind=SummaryKind.SCRIPT, artifact_label="x"
    )
    assert result.summary == "Ok."
    assert result.bullets == ["bullet"]


def test_summarize_fails_loud_on_missing_fields(test_settings: Settings) -> None:
    stub = _StubBackend(responses=[json.dumps({"summary": "only summary"})])
    svc = SummarizationService(test_settings, backend=stub)
    with pytest.raises(SummarizationError):
        svc.summarize_text(
            content="echo hi", kind=SummaryKind.SCRIPT, artifact_label="x"
        )


# ----------------------------------------------------------------------
# API
# ----------------------------------------------------------------------


def test_api_summarize_endpoint(app_client, test_settings: Settings) -> None:
    from extras.research.expert_console.server.services.summarize import (
        SummarizationService,
    )

    stub = _StubBackend()

    # Inject the stub backend via FastAPI dependency override.
    from extras.research.expert_console.server.api.summarize import _summarizer

    def _override_summarizer() -> SummarizationService:
        return SummarizationService(test_settings, backend=stub)

    app_client.app.dependency_overrides[_summarizer] = _override_summarizer

    try:
        response = app_client.post(
            "/api/summarize",
            json={
                "rel_path": "benchmarks/cua_world/environments/moodle_env/env.json",
                "artifact_role": "env_spec",
                "kind_hint": "json",
            },
        )
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["kind"] == "env_spec"
        assert "Moodle" in data["result"]["summary"]
        assert data["result"]["cached"] is False
    finally:
        app_client.app.dependency_overrides.pop(_summarizer, None)


def test_api_summarize_endpoint_missing_file(app_client) -> None:
    response = app_client.post(
        "/api/summarize",
        json={
            "rel_path": "benchmarks/cua_world/environments/moodle_env/nope.json",
        },
    )
    assert response.status_code == 404
