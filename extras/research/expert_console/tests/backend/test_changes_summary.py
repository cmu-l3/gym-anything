"""Tests for the changes-summary service + API."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

import pytest

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.db import (
    reset_engine_for_tests,
    session_scope,
)
from extras.research.expert_console.server.models import (
    AgentRun,
    Feedback,
    FeedbackRoute,
    MemoryTier as MemoryTierEnum,
    Pipeline as PipelineEnum,
    RunStatus,
    Session as SessionRow,
    SessionStatus,
)
from extras.research.expert_console.server.services.changes_summary import (
    ChangesSummary,
    ChangesSummaryError,
    ChangesSummaryService,
)


# ----------------------------------------------------------------------
# Sandbox fixtures
# ----------------------------------------------------------------------


def _isolated_settings(test_settings: Settings, tmp_path: Path) -> Settings:
    repo_root = test_settings.repo_root
    sandbox = tmp_path / "repo"
    sandbox.mkdir()
    (sandbox / "src" / "gym_anything").mkdir(parents=True)
    (sandbox / "src" / "gym_anything" / "__init__.py").write_text("")
    shutil.copytree(
        repo_root / "extras" / "research" / "software_as_env",
        sandbox / "extras" / "research" / "software_as_env",
    )
    shutil.copytree(
        repo_root / "extras" / "research" / "task_generation",
        sandbox / "extras" / "research" / "task_generation",
    )
    envs_root = sandbox / "benchmarks" / "cua_world" / "environments"
    envs_root.mkdir(parents=True)
    src = repo_root / "benchmarks" / "cua_world" / "environments" / "moodle_env"
    dst = envs_root / "moodle_env"
    dst.mkdir()
    shutil.copy(src / "env.json", dst / "env.json")
    (dst / "tasks").mkdir()
    state_dir = tmp_path / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    settings = Settings(
        repo_root=sandbox,
        state_dir=state_dir,
        db_path=state_dir / "ec.sqlite3",
        artifacts_dir=state_dir / "runs",
        claude_bin=test_settings.claude_bin,
    )
    reset_engine_for_tests(settings)
    return settings


def _init_git(root: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=str(root), check=True)
    subprocess.run(
        ["git", "config", "user.email", "test@example.com"],
        cwd=str(root),
        check=True,
    )
    subprocess.run(
        ["git", "config", "user.name", "Test"], cwd=str(root), check=True
    )
    subprocess.run(["git", "add", "-A"], cwd=str(root), check=True)
    subprocess.run(
        ["git", "commit", "-q", "-m", "init"], cwd=str(root), check=True
    )


def _seed_run(
    settings: Settings,
    *,
    env_dir: str = "moodle_env",
    feedback_msg: str = "use real LMS data",
) -> str:
    with session_scope() as db:
        sess = SessionRow(
            title=f"{env_dir} session",
            env_dir=env_dir,
            status=SessionStatus.ACTIVE.value,
        )
        db.add(sess)
        db.flush()
        fb = Feedback(
            session_id=sess.id,
            message=feedback_msg,
            route=FeedbackRoute.CREATOR.value,
            memory_tier=MemoryTierEnum.SPECIFIC.value,
            env_dir=env_dir,
        )
        db.add(fb)
        db.flush()
        run = AgentRun(
            session_id=sess.id,
            feedback_id=fb.id,
            pipeline=PipelineEnum.CREATION_AUDIT.value,
            command=json.dumps(["python", "-m", "x"]),
            status=RunStatus.FINISHED.value,
        )
        db.add(run)
        db.flush()
        return run.id


# ----------------------------------------------------------------------
# Stub backend
# ----------------------------------------------------------------------


class _StubBackend:
    def __init__(self, response: dict[str, Any] | None = None) -> None:
        self.calls: list[dict] = []
        self.response = response or {
            "summary": "Replaced demo course names with real OpenStax course data.",
            "bullets": [
                "Pulls Intro Bio course shell from openstax.org/details/books/biology-2e",
                "Updates verifier to match new course shortname",
                "Adds data_sources block citing OpenStax",
            ],
            "addressed_feedback": "yes",
            "addressed_reason": "Replaces synthetic course with a real OpenStax dataset as requested.",
        }

    def respond(self, *, model, reasoning_effort, system, user, timeout) -> str:
        self.calls.append(
            {"model": model, "effort": reasoning_effort, "user": user}
        )
        return json.dumps(self.response)


# ----------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------


def test_summarize_returns_zero_changes_when_clean(
    test_settings: Settings, tmp_path: Path
) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    run_id = _seed_run(sandboxed)
    backend = _StubBackend()
    svc = ChangesSummaryService(sandboxed, backend=backend)
    result = svc.summarize(run_id)
    assert result.file_count == 0
    assert result.additions == 0
    assert result.addressed_feedback == "no"
    # Skipped the model entirely.
    assert backend.calls == []


def test_summarize_calls_model_when_diff_present(
    test_settings: Settings, tmp_path: Path
) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    run_id = _seed_run(sandboxed)
    # Modify a script after the initial commit so there's a real diff.
    env_root = sandboxed.environments_dir / "moodle_env"
    (env_root / "scripts").mkdir(exist_ok=True)
    (env_root / "scripts" / "install.sh").write_text(
        "#!/bin/bash\necho install REAL data\n", encoding="utf-8"
    )
    backend = _StubBackend()
    svc = ChangesSummaryService(sandboxed, backend=backend)
    result = svc.summarize(run_id)
    assert result.file_count >= 1
    assert result.additions > 0
    assert result.addressed_feedback == "yes"
    assert backend.calls, "model should be called when there are real diffs"
    assert "use real LMS data" in backend.calls[0]["user"]


def test_summarize_caches_until_diff_signature_changes(
    test_settings: Settings, tmp_path: Path
) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    run_id = _seed_run(sandboxed)
    env_root = sandboxed.environments_dir / "moodle_env"
    (env_root / "scripts").mkdir(exist_ok=True)
    (env_root / "scripts" / "install.sh").write_text(
        "#!/bin/bash\necho one\n", encoding="utf-8"
    )
    backend = _StubBackend()
    svc = ChangesSummaryService(sandboxed, backend=backend)
    first = svc.summarize(run_id)
    second = svc.summarize(run_id)
    assert second.cached is True
    assert len(backend.calls) == 1
    # Mutating the diff invalidates the cache by signature.
    (env_root / "scripts" / "install.sh").write_text(
        "#!/bin/bash\necho two\n", encoding="utf-8"
    )
    third = svc.summarize(run_id)
    assert third.cached is False
    assert len(backend.calls) == 2


def test_summarize_force_bypasses_cache(
    test_settings: Settings, tmp_path: Path
) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    run_id = _seed_run(sandboxed)
    env_root = sandboxed.environments_dir / "moodle_env"
    (env_root / "scripts").mkdir(exist_ok=True)
    (env_root / "scripts" / "install.sh").write_text("a\n", encoding="utf-8")
    backend = _StubBackend()
    svc = ChangesSummaryService(sandboxed, backend=backend)
    svc.summarize(run_id)
    svc.summarize(run_id, force=True)
    assert len(backend.calls) == 2


def test_summarize_rejects_unknown_run(test_settings: Settings, tmp_path: Path) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    svc = ChangesSummaryService(sandboxed, backend=_StubBackend())
    with pytest.raises(ChangesSummaryError):
        svc.summarize("does-not-exist")


def test_summarize_validates_response_shape(
    test_settings: Settings, tmp_path: Path
) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    run_id = _seed_run(sandboxed)
    env_root = sandboxed.environments_dir / "moodle_env"
    (env_root / "scripts").mkdir(exist_ok=True)
    (env_root / "scripts" / "install.sh").write_text("x\n", encoding="utf-8")
    backend = _StubBackend(response={"summary": "ok"})  # missing fields
    svc = ChangesSummaryService(sandboxed, backend=backend)
    with pytest.raises(ChangesSummaryError):
        svc.summarize(run_id)


def test_summarize_validates_verdict(
    test_settings: Settings, tmp_path: Path
) -> None:
    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    run_id = _seed_run(sandboxed)
    env_root = sandboxed.environments_dir / "moodle_env"
    (env_root / "scripts").mkdir(exist_ok=True)
    (env_root / "scripts" / "install.sh").write_text("x\n", encoding="utf-8")
    backend = _StubBackend(
        response={
            "summary": "ok",
            "bullets": ["a"],
            "addressed_feedback": "mostly",  # invalid
            "addressed_reason": "n/a",
        }
    )
    svc = ChangesSummaryService(sandboxed, backend=backend)
    with pytest.raises(ChangesSummaryError):
        svc.summarize(run_id)


# ----------------------------------------------------------------------
# API
# ----------------------------------------------------------------------


def test_api_changes_summary(test_settings: Settings, tmp_path: Path) -> None:
    """Through the FastAPI app — verifies route wiring + 404 behavior."""
    from fastapi.testclient import TestClient
    from extras.research.expert_console.server.app import create_app
    from extras.research.expert_console.server.config import get_settings
    from extras.research.expert_console.server.api.runs import (
        _changes_summary_service,
    )

    sandboxed = _isolated_settings(test_settings, tmp_path)
    _init_git(sandboxed.repo_root)
    run_id = _seed_run(sandboxed)
    env_root = sandboxed.environments_dir / "moodle_env"
    (env_root / "scripts").mkdir(exist_ok=True)
    (env_root / "scripts" / "install.sh").write_text("real data\n", encoding="utf-8")

    backend = _StubBackend()
    app = create_app(settings=sandboxed, skip_runtime_validation=True)
    app.dependency_overrides[get_settings] = lambda: sandboxed
    app.dependency_overrides[_changes_summary_service] = lambda: ChangesSummaryService(
        sandboxed, backend=backend
    )
    with TestClient(app) as client:
        r404 = client.get("/api/runs/nope/changes-summary")
        assert r404.status_code == 404, r404.text
        ok = client.get(f"/api/runs/{run_id}/changes-summary").json()
        assert ok["addressed_feedback"] == "yes"
        assert "OpenStax" in ok["summary"]
        # Second call hits the cache.
        ok2 = client.get(f"/api/runs/{run_id}/changes-summary").json()
        assert ok2["cached"] is True
