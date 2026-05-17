"""Tests for the settings (diagnostics + preferences) endpoints."""

from __future__ import annotations

import json

import pytest

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.services.preferences import (
    Preferences,
    PreferencesError,
    PreferencesService,
)


# ----------------------------------------------------------------------
# PreferencesService unit tests
# ----------------------------------------------------------------------


def test_preferences_initial_matches_settings(test_settings: Settings) -> None:
    svc = PreferencesService(test_settings)
    prefs = svc.get()
    assert prefs.summarize_model == test_settings.summarize_model
    assert prefs.summarize_reasoning_effort == test_settings.summarize_reasoning_effort


def test_preferences_update_persists(test_settings: Settings) -> None:
    svc = PreferencesService(test_settings)
    new = svc.update({"summarize_reasoning_effort": "high"})
    assert new.summarize_reasoning_effort == "high"
    again = PreferencesService(test_settings)
    assert again.get().summarize_reasoning_effort == "high"


def test_preferences_update_rejects_unknown_key(test_settings: Settings) -> None:
    svc = PreferencesService(test_settings)
    with pytest.raises(PreferencesError):
        svc.update({"unknown_thing": 1})


def test_preferences_update_rejects_invalid_effort(test_settings: Settings) -> None:
    svc = PreferencesService(test_settings)
    with pytest.raises(PreferencesError):
        svc.update({"summarize_reasoning_effort": "ultra"})


def test_preferences_update_rejects_bad_threshold(test_settings: Settings) -> None:
    svc = PreferencesService(test_settings)
    with pytest.raises(PreferencesError):
        svc.update({"integrity_threshold": 5})


def test_preferences_reset(test_settings: Settings) -> None:
    svc = PreferencesService(test_settings)
    svc.update({"summarize_reasoning_effort": "high"})
    reset = svc.reset()
    assert reset.summarize_reasoning_effort == test_settings.summarize_reasoning_effort


def test_preferences_corrupt_file_fails_loud(test_settings: Settings) -> None:
    svc = PreferencesService(test_settings)
    svc.path.write_text("not json {", encoding="utf-8")
    with pytest.raises(PreferencesError):
        svc.get()


# ----------------------------------------------------------------------
# API tests
# ----------------------------------------------------------------------


def test_api_diagnostics(app_client, test_settings: Settings) -> None:
    response = app_client.get("/api/settings/diagnostics")
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["repo_root"] == str(test_settings.repo_root)
    assert data["env_count"] >= 100
    assert data["expert_feedback_files_present"] is True
    assert data["openai_api_key_present"] is True  # set in test conftest
    assert isinstance(data["claude_bin"], str)


def test_api_get_preferences(app_client) -> None:
    response = app_client.get("/api/settings/preferences")
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["summarize_model"] == "gpt-5.4"
    assert data["summarize_reasoning_effort"] == "medium"


def test_api_update_preferences(app_client) -> None:
    response = app_client.put(
        "/api/settings/preferences",
        json={"summarize_reasoning_effort": "high"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["summarize_reasoning_effort"] == "high"
    response = app_client.get("/api/settings/preferences")
    assert response.json()["summarize_reasoning_effort"] == "high"


def test_api_update_rejects_invalid(app_client) -> None:
    response = app_client.put(
        "/api/settings/preferences",
        json={"summarize_reasoning_effort": "ultra"},
    )
    assert response.status_code == 400


def test_api_update_rejects_unknown_key(app_client) -> None:
    # extra='forbid' on PreferencesPayload returns 422 from pydantic.
    response = app_client.put(
        "/api/settings/preferences",
        json={"definitely_not_a_pref": 5},
    )
    assert response.status_code == 422


def test_api_reset_preferences(app_client) -> None:
    app_client.put(
        "/api/settings/preferences",
        json={"summarize_reasoning_effort": "high"},
    )
    response = app_client.post("/api/settings/preferences/reset")
    assert response.status_code == 200
    assert response.json()["summarize_reasoning_effort"] == "medium"


# ----------------------------------------------------------------------
# Summarize service picks up live preferences
# ----------------------------------------------------------------------


def test_summarize_service_reads_live_preferences(test_settings: Settings) -> None:
    from extras.research.expert_console.server.services.summarize import (
        SummarizationService,
    )

    prefs = PreferencesService(test_settings)
    svc = SummarizationService(test_settings, preferences=prefs)
    assert svc.reasoning_effort == "medium"
    prefs.update({"summarize_reasoning_effort": "high"})
    assert svc.reasoning_effort == "high"
