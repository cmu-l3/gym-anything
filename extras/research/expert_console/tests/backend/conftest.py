"""Shared pytest fixtures for expert console backend tests."""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path
from typing import Iterator

import pytest
from fastapi.testclient import TestClient

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.db import (
    init_db,
    reset_engine_for_tests,
    session_scope,
)


# ----------------------------------------------------------------------
# Repo-level helpers
# ----------------------------------------------------------------------


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return _repo_root()


# ----------------------------------------------------------------------
# Settings — built against a temp state dir and a stub claude binary so
# `validate_runtime()` passes without touching real APIs.
# ----------------------------------------------------------------------


@pytest.fixture
def stub_claude(tmp_path: Path) -> Path:
    """Drop a fake `claude` shim so validation passes in tests."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    claude = bin_dir / "claude"
    claude.write_text("#!/usr/bin/env bash\nexit 0\n")
    claude.chmod(0o755)
    return claude


@pytest.fixture
def test_settings(
    tmp_path: Path,
    stub_claude: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> Settings:
    state_dir = tmp_path / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    monkeypatch.setenv("OPENAI_API_KEY", "test-openai-key")
    monkeypatch.setenv("CLAUDE_BIN", str(stub_claude))
    # Make sure the validator's PATH lookup also finds claude.
    monkeypatch.setenv("PATH", f"{stub_claude.parent}{os.pathsep}{os.environ.get('PATH', '')}")
    settings = Settings(
        state_dir=state_dir,
        db_path=state_dir / "test.sqlite3",
        artifacts_dir=state_dir / "runs",
        claude_bin=str(stub_claude),
    )
    reset_engine_for_tests(settings)
    return settings


@pytest.fixture
def app_client(test_settings: Settings) -> Iterator[TestClient]:
    from extras.research.expert_console.server.app import create_app
    from extras.research.expert_console.server.config import get_settings

    app = create_app(settings=test_settings, skip_runtime_validation=True)
    app.dependency_overrides[get_settings] = lambda: test_settings
    try:
        with TestClient(app) as client:
            yield client
    finally:
        app.dependency_overrides.clear()


@pytest.fixture
def db_session(test_settings: Settings):
    init_db(test_settings)
    with session_scope() as session:
        yield session
