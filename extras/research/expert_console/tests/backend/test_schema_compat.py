"""Tests for the schema-mismatch detector in db.init_db."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.db import (
    SchemaMismatchError,
    init_db,
    reset_engine_for_tests,
)


def test_init_db_fails_loud_on_outdated_schema(
    test_settings: Settings, tmp_path: Path
) -> None:
    # Drop a sqlite file with a `sessions` table missing the `title` column.
    db_path = tmp_path / "outdated.sqlite3"
    con = sqlite3.connect(db_path)
    con.execute(
        "CREATE TABLE sessions (id TEXT PRIMARY KEY, status TEXT, created_at TEXT)"
    )
    con.commit()
    con.close()

    settings = Settings(
        repo_root=test_settings.repo_root,
        state_dir=tmp_path,
        db_path=db_path,
        artifacts_dir=tmp_path / "runs",
        claude_bin=test_settings.claude_bin,
    )
    with pytest.raises(SchemaMismatchError) as exc_info:
        reset_engine_for_tests(settings)
    msg = str(exc_info.value)
    assert "sessions" in msg
    assert "title" in msg
    assert str(db_path) in msg


def test_init_db_succeeds_on_fresh_state(
    test_settings: Settings, tmp_path: Path
) -> None:
    db_path = tmp_path / "fresh.sqlite3"
    settings = Settings(
        repo_root=test_settings.repo_root,
        state_dir=tmp_path,
        db_path=db_path,
        artifacts_dir=tmp_path / "runs",
        claude_bin=test_settings.claude_bin,
    )
    engine = reset_engine_for_tests(settings)
    assert db_path.is_file()
    # Re-running on the now-existing schema should still succeed.
    reset_engine_for_tests(settings)
