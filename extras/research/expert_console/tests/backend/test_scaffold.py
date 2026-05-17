"""Tests for the backend scaffold — settings, db, app boot."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.db import (
    get_engine,
    init_db,
    session_scope,
)
from extras.research.expert_console.server.models import (
    AgentRun,
    Feedback,
    FeedbackRoute,
    MemoryTier,
    Pipeline,
    RunStatus,
    Session,
    SessionStatus,
)


# ----------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------


def test_settings_resolve_repo_paths(test_settings: Settings) -> None:
    assert test_settings.repo_root.is_dir()
    assert (test_settings.repo_root / "src" / "gym_anything").is_dir()
    assert test_settings.environments_dir.is_dir()
    assert test_settings.creation_audit_memory_dir.is_dir()
    assert test_settings.propose_amplify_memory_dir.is_dir()


def test_expert_feedback_files_exist(test_settings: Settings) -> None:
    assert test_settings.expert_feedback_creation_path.is_file()
    assert test_settings.expert_feedback_audit_path.is_file()
    assert test_settings.expert_feedback_propose_path.is_file()


def test_validate_runtime_passes_when_prereqs_present(
    test_settings: Settings,
) -> None:
    test_settings.validate_runtime()


def test_validate_runtime_fails_loud_without_openai_key(
    test_settings: Settings,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    with pytest.raises(RuntimeError, match="OPENAI_API_KEY"):
        test_settings.validate_runtime()


def test_validate_runtime_fails_loud_without_claude(
    test_settings: Settings,
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    missing_path = tmp_path / "does_not_exist"
    settings = Settings(
        state_dir=test_settings.state_dir,
        db_path=test_settings.db_path,
        artifacts_dir=test_settings.artifacts_dir,
        claude_bin=str(missing_path),
    )
    with pytest.raises(RuntimeError, match="claude"):
        settings.validate_runtime()


# ----------------------------------------------------------------------
# DB / models
# ----------------------------------------------------------------------


def test_db_initialises_and_creates_tables(test_settings: Settings) -> None:
    engine = init_db(test_settings)
    inspector = engine.connect()
    try:
        names = engine.dialect.get_table_names(inspector)
    finally:
        inspector.close()
    assert "sessions" in names
    assert "feedbacks" in names
    assert "agent_runs" in names
    assert "run_logs" in names


def test_session_feedback_run_round_trip(test_settings: Settings) -> None:
    init_db(test_settings)
    with session_scope() as db:
        sess = Session(
            title="Moodle: enroll_student",
            env_dir="moodle_env",
            task_id="enroll_student",
            status=SessionStatus.ACTIVE.value,
        )
        db.add(sess)
        db.flush()
        fb = Feedback(
            session_id=sess.id,
            message="use real data, not demo data",
            route=FeedbackRoute.CREATOR.value,
            memory_tier=MemoryTier.SPECIFIC.value,
            env_dir="moodle_env",
        )
        db.add(fb)
        db.flush()
        run = AgentRun(
            session_id=sess.id,
            feedback_id=fb.id,
            pipeline=Pipeline.CREATION_AUDIT.value,
            command='["claude", "-p", "..."]',
            status=RunStatus.PENDING.value,
        )
        db.add(run)
        db.flush()
        run_id = run.id

    with session_scope() as db:
        run = db.get(AgentRun, run_id)
        assert run is not None
        assert run.feedback is not None
        assert run.feedback.message == "use real data, not demo data"
        assert run.session.env_dir == "moodle_env"


# ----------------------------------------------------------------------
# App
# ----------------------------------------------------------------------


def test_health_endpoint(app_client) -> None:
    response = app_client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_config_endpoint(app_client, test_settings: Settings) -> None:
    response = app_client.get("/api/config")
    assert response.status_code == 200
    data = response.json()
    assert data["repo_root"] == str(test_settings.repo_root)
    assert data["summarize_model"] == "gpt-5.4"
    assert data["summarize_reasoning_effort"] == "medium"
