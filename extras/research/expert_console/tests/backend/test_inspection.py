"""Tests for the inspection service against real CUA-World envs."""

from __future__ import annotations

from pathlib import Path

import pytest

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.services.inspection import (
    ArtifactKind,
    InspectionError,
    InspectionService,
)


# ----------------------------------------------------------------------
# Software listing
# ----------------------------------------------------------------------


def test_list_software_returns_real_envs(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    items = svc.list_software()
    by_dir = {item.env_dir: item for item in items}
    assert "moodle_env" in by_dir, "moodle_env is the canonical example"
    moodle = by_dir["moodle_env"]
    assert moodle.spec_id.startswith("moodle_env")
    assert moodle.description is not None
    assert moodle.task_count > 0
    # CUA-World has 200+ env folders; the count must be substantial.
    assert len(items) >= 100


def test_list_software_skips_dotdirs(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    items = svc.list_software()
    for item in items:
        assert not item.env_dir.startswith((".", "__"))


# ----------------------------------------------------------------------
# Task listing
# ----------------------------------------------------------------------


def test_list_tasks_for_moodle(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    tasks = svc.list_tasks("moodle_env")
    assert tasks, "moodle_env must have tasks"
    by_id = {t.task_id: t for t in tasks}
    assert "audit_student_course_access" in by_id
    audit = by_id["audit_student_course_access"]
    assert audit.description is not None
    assert audit.success_mode in ("program", "image_match", "multi", "vlm_checklist")
    assert isinstance(audit.has_vlm_checklist, bool)


def test_list_tasks_missing_env(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    with pytest.raises(InspectionError):
        svc.list_tasks("definitely_not_an_env")


def test_list_tasks_path_traversal_blocked(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    with pytest.raises(InspectionError):
        svc.list_tasks("../etc")


# ----------------------------------------------------------------------
# Env view
# ----------------------------------------------------------------------


def test_get_env_view_moodle(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    view = svc.get_env_view("moodle_env")
    assert view.env_dir == "moodle_env"
    assert view.spec_id.startswith("moodle_env")
    assert "moodle" in (view.tags or [])
    assert view.base_preset is not None
    # Must surface env.json + at least one install + one setup script.
    roles = {a.role for a in view.artifacts}
    assert "env_spec" in roles
    assert "install_script" in roles or "setup_script" in roles
    # Moodle has tasks
    assert view.tasks


def test_get_env_view_external_sources(test_settings: Settings) -> None:
    """At least one Moodle script downloads from an upstream URL."""
    svc = InspectionService(test_settings)
    view = svc.get_env_view("moodle_env")
    # External sources may or may not exist depending on installation
    # style; if any exist, they must point at a real URL discovered in
    # a script file under env_dir.
    for source in view.external_sources:
        assert source.url.startswith(("http://", "https://"))
        assert "moodle_env" in source.discovered_in


def test_get_env_view_invalid(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    with pytest.raises(InspectionError):
        svc.get_env_view("not_a_real_env")


# ----------------------------------------------------------------------
# Task view
# ----------------------------------------------------------------------


def test_get_task_view_moodle(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    view = svc.get_task_view("moodle_env", "audit_student_course_access")
    assert view.env_dir == "moodle_env"
    assert view.task_id == "audit_student_course_access"
    assert view.description and "Jane Smith" in view.description
    assert view.success_mode == "program"
    assert view.vlm_checklist_present is True
    roles = {a.role for a in view.artifacts}
    assert "task_spec" in roles
    assert "task_setup" in roles
    assert "verifier" in roles
    assert "vlm_checklist" in roles


def test_get_task_view_missing_task(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    with pytest.raises(InspectionError):
        svc.get_task_view("moodle_env", "nope_not_a_task")


# ----------------------------------------------------------------------
# Artifact content
# ----------------------------------------------------------------------


def test_artifact_content_reads_real_file(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    view = svc.get_task_view("moodle_env", "audit_student_course_access")
    task_spec = next(a for a in view.artifacts if a.role == "task_spec")
    content = svc.get_artifact_content(task_spec.rel_path)
    assert content.kind == ArtifactKind.JSON
    assert content.text is not None
    assert '"task_id"' in content.text or '"id":' in content.text


def test_artifact_content_path_traversal_blocked(test_settings: Settings) -> None:
    svc = InspectionService(test_settings)
    with pytest.raises(InspectionError):
        svc.get_artifact_content("../../etc/passwd")


# ----------------------------------------------------------------------
# API
# ----------------------------------------------------------------------


def test_api_list_software(app_client) -> None:
    response = app_client.get("/api/software")
    assert response.status_code == 200
    data = response.json()
    assert "items" in data and isinstance(data["items"], list)
    assert data["count"] == len(data["items"])
    assert any(item["env_dir"] == "moodle_env" for item in data["items"])


def test_api_get_env(app_client) -> None:
    response = app_client.get("/api/software/moodle_env")
    assert response.status_code == 200
    data = response.json()
    assert data["env_dir"] == "moodle_env"
    assert data["tasks"]


def test_api_get_task(app_client) -> None:
    response = app_client.get(
        "/api/software/moodle_env/tasks/audit_student_course_access"
    )
    assert response.status_code == 200
    data = response.json()
    assert data["task_id"] == "audit_student_course_access"
    assert data["vlm_checklist_present"] is True


def test_api_missing_env_404(app_client) -> None:
    response = app_client.get("/api/software/no_such_env")
    assert response.status_code == 404


def test_api_artifact_content(app_client) -> None:
    response = app_client.get(
        "/api/software/moodle_env/artifact",
        params={"rel_path": "benchmarks/cua_world/environments/moodle_env/env.json"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["kind"] == "json"
    assert data["text"] is not None
