"""Tests for the pipeline dispatch service + feedback/runs API.

Subprocess launching is stubbed via a FakeLauncher that returns a
process running a small bash script written to disk. The script
prints deterministic lines and exits cleanly, exercising the full
streaming/persistence path without needing claude or codex on PATH.
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import textwrap
import time
from pathlib import Path
from typing import Iterator

import pytest
from fastapi.testclient import TestClient

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.db import (
    reset_engine_for_tests,
    session_scope,
)
from extras.research.expert_console.server.models import (
    AgentRun,
    Pipeline as PipelineEnum,
    RunStatus,
)
from extras.research.expert_console.server.services.dispatch import (
    DispatchError,
    DispatchService,
    FeedbackPayload,
    SubprocessLauncher,
)
from extras.research.expert_console.server.services.memory import (
    MemoryTier,
)
from extras.research.expert_console.server.models import FeedbackRoute


# ----------------------------------------------------------------------
# Sandbox fixture (copies memory + envs into tmp, isolated SQLite)
# ----------------------------------------------------------------------


@pytest.fixture
def sandboxed_settings(test_settings: Settings, tmp_path: Path) -> Settings:
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
    # Need at least one env directory present so dispatcher's
    # env_dir validation passes; copy the moodle_env minimal shape.
    envs_root = sandbox / "benchmarks" / "cua_world" / "environments"
    envs_root.mkdir(parents=True)
    src_moodle = repo_root / "benchmarks" / "cua_world" / "environments" / "moodle_env"
    dst_moodle = envs_root / "moodle_env"
    dst_moodle.mkdir()
    shutil.copy(src_moodle / "env.json", dst_moodle / "env.json")
    (dst_moodle / "tasks").mkdir()
    # Mirror just one task for task-level dispatch tests.
    src_task = src_moodle / "tasks" / "audit_student_course_access"
    dst_task = dst_moodle / "tasks" / "audit_student_course_access"
    shutil.copytree(src_task, dst_task)

    state_dir = tmp_path / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    settings = Settings(
        repo_root=sandbox,
        state_dir=state_dir,
        db_path=state_dir / "test.sqlite3",
        artifacts_dir=state_dir / "runs",
        claude_bin=test_settings.claude_bin,
    )
    reset_engine_for_tests(settings)
    return settings


# ----------------------------------------------------------------------
# Fake launcher — runs a small bash script the test controls.
# ----------------------------------------------------------------------


class FakeLauncher(SubprocessLauncher):
    """Captures commands and launches a deterministic shell script
    instead of the real pipeline.
    """

    def __init__(self, *, script: str | None = None, sleep_before_exit: float = 0.0) -> None:
        self.calls: list[tuple[list[str], Path]] = []
        self.script = script
        self.sleep_before_exit = sleep_before_exit

    def start(self, command: list[str], *, cwd: Path) -> tuple[subprocess.Popen, int]:
        self.calls.append((list(command), cwd))
        script_text = self.script or textwrap.dedent(
            """\
            #!/usr/bin/env bash
            echo "=== Initial Attempt ==="
            echo "claude doing things..."
            echo "=== Audit Round 1 ==="
            echo "audit pass"
            """
        )
        if self.sleep_before_exit > 0:
            script_text += f"sleep {self.sleep_before_exit}\n"
        script_path = cwd / f"_fake_pipeline_{os.getpid()}_{time.time_ns()}.sh"
        script_path.write_text(script_text)
        script_path.chmod(0o755)
        proc = subprocess.Popen(
            ["bash", str(script_path)],
            cwd=str(cwd),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            start_new_session=True,
        )
        pgid = os.getpgid(proc.pid)
        return proc, pgid


# ----------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------


def _make_dispatcher(
    settings: Settings, launcher: SubprocessLauncher | None = None
) -> DispatchService:
    return DispatchService(settings, subprocess_launcher=launcher or FakeLauncher())


def _payload(**kwargs) -> FeedbackPayload:
    defaults: dict = {
        "session_id": None,
        "message": "use real data, not demo",
        "route": FeedbackRoute.CREATOR,
        "memory_tier": MemoryTier.GENERAL,
        "suggest_checklist_change": False,
        "env_dir": None,
        "task_id": None,
        "is_new_task": False,
    }
    defaults.update(kwargs)
    return FeedbackPayload(**defaults)


def test_dispatch_validation_rejects_empty_message(sandboxed_settings: Settings) -> None:
    dispatcher = _make_dispatcher(sandboxed_settings)
    with pytest.raises(DispatchError):
        dispatcher.submit(_payload(message="   "))


def test_dispatch_validation_task_without_env(sandboxed_settings: Settings) -> None:
    dispatcher = _make_dispatcher(sandboxed_settings)
    with pytest.raises(DispatchError):
        dispatcher.submit(_payload(task_id="enroll_student"))


def test_dispatch_validation_specific_without_env(sandboxed_settings: Settings) -> None:
    dispatcher = _make_dispatcher(sandboxed_settings)
    with pytest.raises(DispatchError):
        dispatcher.submit(
            _payload(memory_tier=MemoryTier.SPECIFIC, env_dir=None)
        )


def test_dispatch_validation_unknown_env(sandboxed_settings: Settings) -> None:
    dispatcher = _make_dispatcher(sandboxed_settings)
    with pytest.raises(DispatchError):
        dispatcher.submit(_payload(env_dir="no_such_env"))


def test_dispatch_validation_unknown_task(sandboxed_settings: Settings) -> None:
    dispatcher = _make_dispatcher(sandboxed_settings)
    with pytest.raises(DispatchError):
        dispatcher.submit(
            _payload(env_dir="moodle_env", task_id="nope_not_a_task")
        )


# ----------------------------------------------------------------------
# Memory-only submission (env_dir=None)
# ----------------------------------------------------------------------


def test_memory_only_submission_skips_dispatch(sandboxed_settings: Settings) -> None:
    launcher = FakeLauncher()
    dispatcher = _make_dispatcher(sandboxed_settings, launcher=launcher)
    result = dispatcher.submit(
        _payload(message="all envs should prefer real data")
    )
    assert result.dispatched is False
    assert result.run_id is None
    assert result.command is None
    assert launcher.calls == []
    text = sandboxed_settings.expert_feedback_creation_path.read_text(encoding="utf-8")
    assert "real data" in text


# ----------------------------------------------------------------------
# Creator + audit routing (env-level dispatch)
# ----------------------------------------------------------------------


def _wait_for_terminal(
    dispatcher: DispatchService, run_id: str, timeout: float = 5.0
) -> AgentRun:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        run = dispatcher.get_run(run_id)
        if run.status in {
            RunStatus.FINISHED.value,
            RunStatus.FAILED.value,
            RunStatus.STOPPED.value,
        }:
            return run
        time.sleep(0.1)
    raise AssertionError(f"Run {run_id} did not finish in {timeout}s")


def test_creator_route_dispatches_edit_env(
    sandboxed_settings: Settings,
) -> None:
    launcher = FakeLauncher()
    dispatcher = _make_dispatcher(sandboxed_settings, launcher=launcher)
    result = dispatcher.submit(
        _payload(
            message="rebuild moodle env with real LMS data",
            env_dir="moodle_env",
            memory_tier=MemoryTier.SPECIFIC,
            route=FeedbackRoute.CREATOR,
        )
    )
    assert result.dispatched is True
    assert result.pipeline is PipelineEnum.CREATION_AUDIT
    assert result.command[1] == "-m"
    assert "creation_audit.edit_env" in result.command[2]
    assert "moodle_env" in result.command
    route_idx = result.command.index("--route") + 1
    assert result.command[route_idx] == "creator"
    # Wait for run to finish, check logs persisted
    run = _wait_for_terminal(dispatcher, result.run_id)
    assert run.status == RunStatus.FINISHED.value


def test_audit_route_dispatches_edit_env_audit(sandboxed_settings: Settings) -> None:
    launcher = FakeLauncher()
    dispatcher = _make_dispatcher(sandboxed_settings, launcher=launcher)
    result = dispatcher.submit(
        _payload(
            message="audit moodle for demo data",
            env_dir="moodle_env",
            memory_tier=MemoryTier.SPECIFIC,
            route=FeedbackRoute.AUDIT,
        )
    )
    assert result.dispatched is True
    assert "creation_audit.edit_env" in result.command[2]
    route_idx = result.command.index("--route") + 1
    assert result.command[route_idx] == "audit"
    text = sandboxed_settings.expert_feedback_audit_path.read_text(encoding="utf-8")
    assert "audit moodle for demo data" in text


# ----------------------------------------------------------------------
# Task-level routing (edit_task / propose_and_amplify)
# ----------------------------------------------------------------------


def test_task_edit_routes_to_edit_task(sandboxed_settings: Settings) -> None:
    launcher = FakeLauncher()
    dispatcher = _make_dispatcher(sandboxed_settings, launcher=launcher)
    result = dispatcher.submit(
        _payload(
            message="bulk-import 50 students instead of one",
            env_dir="moodle_env",
            task_id="audit_student_course_access",
            memory_tier=MemoryTier.SPECIFIC,
        )
    )
    assert result.pipeline is PipelineEnum.PROPOSE_AND_AMPLIFY
    assert "propose_and_amplify.method" in result.command[2]
    stage_idx = result.command.index("--stage") + 1
    assert result.command[stage_idx] == "edit"
    target_idx = result.command.index("--target-task") + 1
    assert result.command[target_idx] == "audit_student_course_access"
    text = sandboxed_settings.expert_feedback_propose_path.read_text(encoding="utf-8")
    assert "bulk-import 50 students" in text


def test_new_task_routes_to_full_pipeline(sandboxed_settings: Settings) -> None:
    launcher = FakeLauncher()
    dispatcher = _make_dispatcher(sandboxed_settings, launcher=launcher)
    result = dispatcher.submit(
        _payload(
            message="generate a course-archival task",
            env_dir="moodle_env",
            task_id=None,
            is_new_task=True,
            memory_tier=MemoryTier.SPECIFIC,
        )
    )
    assert result.pipeline is PipelineEnum.PROPOSE_AND_AMPLIFY
    stage_idx = result.command.index("--stage") + 1
    assert result.command[stage_idx] == "all"
    assert "--target-task" not in result.command


# ----------------------------------------------------------------------
# Stop control
# ----------------------------------------------------------------------


def test_stop_run_kills_process(sandboxed_settings: Settings) -> None:
    # Use a long-running fake script the dispatcher can interrupt.
    launcher = FakeLauncher(script="#!/usr/bin/env bash\necho start\nsleep 10\necho late\n")
    dispatcher = _make_dispatcher(sandboxed_settings, launcher=launcher)
    result = dispatcher.submit(
        _payload(
            message="stop me",
            env_dir="moodle_env",
            memory_tier=MemoryTier.SPECIFIC,
            route=FeedbackRoute.AUDIT,
        )
    )
    # Wait until the subprocess has actually started, then stop it.
    time.sleep(0.5)
    assert dispatcher.stop_run(result.run_id) is True
    run = _wait_for_terminal(dispatcher, result.run_id, timeout=5)
    assert run.status in {RunStatus.STOPPED.value, RunStatus.FAILED.value}


# ----------------------------------------------------------------------
# API
# ----------------------------------------------------------------------


@pytest.fixture
def sandboxed_client(sandboxed_settings: Settings) -> Iterator[TestClient]:
    from extras.research.expert_console.server.app import create_app
    from extras.research.expert_console.server.config import get_settings

    launcher = FakeLauncher()
    app = create_app(
        settings=sandboxed_settings,
        skip_runtime_validation=True,
        subprocess_launcher=launcher,
    )
    app.dependency_overrides[get_settings] = lambda: sandboxed_settings
    app.state.launcher = launcher
    try:
        with TestClient(app) as client:
            yield client
    finally:
        app.dependency_overrides.clear()


def test_api_submit_feedback_memory_only(sandboxed_client: TestClient) -> None:
    response = sandboxed_client.post(
        "/api/feedback",
        json={
            "message": "prefer real data globally",
            "route": "creator",
            "memory_tier": "general",
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["dispatched"] is False
    assert data["run_id"] is None
    assert "expert_feedback.md" in data["memory_entry"]["rel_path"]


def test_api_submit_feedback_creator_dispatch(sandboxed_client: TestClient) -> None:
    response = sandboxed_client.post(
        "/api/feedback",
        json={
            "message": "rebuild moodle with real LMS data",
            "route": "creator",
            "memory_tier": "specific",
            "env_dir": "moodle_env",
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["dispatched"] is True
    assert data["pipeline"] == "creation_audit"
    assert data["run_id"]
    # Run details endpoint reports the run
    run_response = sandboxed_client.get(f"/api/runs/{data['run_id']}")
    assert run_response.status_code == 200
    # Wait for run to finish (poll status)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        rr = sandboxed_client.get(f"/api/runs/{data['run_id']}").json()
        if rr["status"] in {"finished", "failed", "stopped"}:
            break
        time.sleep(0.1)
    rr = sandboxed_client.get(f"/api/runs/{data['run_id']}").json()
    assert rr["status"] == "finished"
    log_lines = [log["line"] for log in rr["logs"]]
    assert any("Initial Attempt" in line for line in log_lines)


def test_api_session_list_and_detail(sandboxed_client: TestClient) -> None:
    # Submit one feedback to create a session.
    sub = sandboxed_client.post(
        "/api/feedback",
        json={
            "message": "test session creation",
            "route": "creator",
            "memory_tier": "specific",
            "env_dir": "moodle_env",
        },
    ).json()
    sid = sub["session_id"]
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if sandboxed_client.get(f"/api/runs/{sub['run_id']}").json()["status"] in {
            "finished",
            "failed",
            "stopped",
        }:
            break
        time.sleep(0.1)

    list_resp = sandboxed_client.get("/api/sessions").json()
    assert any(s["id"] == sid for s in list_resp)
    detail = sandboxed_client.get(f"/api/sessions/{sid}").json()
    assert detail["env_dir"] == "moodle_env"
    assert detail["feedback_count"] >= 1
    assert detail["run_count"] >= 1


def test_api_stop_run(sandboxed_client: TestClient) -> None:
    launcher: FakeLauncher = sandboxed_client.app.state.launcher
    launcher.script = "#!/usr/bin/env bash\necho start\nsleep 10\necho late\n"
    sub = sandboxed_client.post(
        "/api/feedback",
        json={
            "message": "stop please",
            "route": "audit",
            "memory_tier": "specific",
            "env_dir": "moodle_env",
        },
    ).json()
    time.sleep(0.5)
    stop = sandboxed_client.post(f"/api/runs/{sub['run_id']}/stop")
    assert stop.status_code == 200
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        rr = sandboxed_client.get(f"/api/runs/{sub['run_id']}").json()
        if rr["status"] in {"stopped", "failed", "finished"}:
            break
        time.sleep(0.1)
    rr = sandboxed_client.get(f"/api/runs/{sub['run_id']}").json()
    assert rr["status"] in {"stopped", "failed"}


def test_api_sse_stream_emits_logs(sandboxed_client: TestClient) -> None:
    sub = sandboxed_client.post(
        "/api/feedback",
        json={
            "message": "stream test",
            "route": "creator",
            "memory_tier": "specific",
            "env_dir": "moodle_env",
        },
    ).json()
    # Read raw SSE response — TestClient streams chunks.
    with sandboxed_client.stream("GET", f"/api/runs/{sub['run_id']}/stream") as resp:
        assert resp.status_code == 200
        body = b""
        deadline = time.monotonic() + 5
        for chunk in resp.iter_bytes():
            body += chunk
            if b"event: status" in body and b'"status": "finished"' in body:
                break
            if time.monotonic() > deadline:
                break
        assert b"event: log" in body
        assert b"Initial Attempt" in body
