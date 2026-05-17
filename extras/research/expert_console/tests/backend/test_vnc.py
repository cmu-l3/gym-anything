"""Tests for the VNC service + WS proxy.

We spin up a tiny TCP echo server in-process and point the
FakeVNCProvider at it, so we can exercise the proxy end-to-end without
needing a real VNC daemon.
"""

from __future__ import annotations

import asyncio
import socket
import threading
from pathlib import Path
from typing import Iterator

import pytest
import shutil
from fastapi.testclient import TestClient

from extras.research.expert_console.server.config import Settings
from extras.research.expert_console.server.db import reset_engine_for_tests
from extras.research.expert_console.server.services.vnc import (
    FakeVNCProvider,
    VNCError,
    VNCService,
    free_port,
)


# ----------------------------------------------------------------------
# In-process TCP echo server
# ----------------------------------------------------------------------


class EchoServer:
    """Synchronous TCP echo server, runs in a thread, echoes bytes back."""

    def __init__(self) -> None:
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind(("127.0.0.1", 0))
        self._sock.listen(4)
        self.port = self._sock.getsockname()[1]
        self._stop = threading.Event()
        self._clients: list[socket.socket] = []
        self._thread = threading.Thread(
            target=self._serve, daemon=True, name="echo-server"
        )

    def start(self) -> "EchoServer":
        self._thread.start()
        return self

    def stop(self) -> None:
        self._stop.set()
        try:
            self._sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self._sock.close()
        for c in list(self._clients):
            try:
                c.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            c.close()
        self._thread.join(timeout=1)

    def _serve(self) -> None:
        self._sock.settimeout(0.2)
        while not self._stop.is_set():
            try:
                client, _ = self._sock.accept()
            except (socket.timeout, OSError):
                continue
            self._clients.append(client)
            threading.Thread(
                target=self._handle, args=(client,), daemon=True
            ).start()

    def _handle(self, client: socket.socket) -> None:
        try:
            while not self._stop.is_set():
                data = client.recv(4096)
                if not data:
                    return
                client.sendall(data)
        except OSError:
            return
        finally:
            try:
                client.close()
            except OSError:
                pass


@pytest.fixture
def echo_server() -> Iterator[EchoServer]:
    srv = EchoServer().start()
    try:
        yield srv
    finally:
        srv.stop()


# ----------------------------------------------------------------------
# Sandboxed settings (need at least moodle_env for env-dir validation)
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
    envs_root = sandbox / "benchmarks" / "cua_world" / "environments"
    envs_root.mkdir(parents=True)
    src = repo_root / "benchmarks" / "cua_world" / "environments" / "moodle_env"
    (envs_root / "moodle_env").mkdir()
    shutil.copy(src / "env.json", envs_root / "moodle_env" / "env.json")

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
# Service lifecycle
# ----------------------------------------------------------------------


def test_start_returns_running_session(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    provider = FakeVNCProvider(port_factory=lambda: echo_server.port)
    svc = VNCService(sandboxed_settings, provider=provider)
    session = svc.start("moodle_env", await_ready=True)
    assert session.status == "running"
    assert session.vnc_port == echo_server.port
    assert session.vnc_password == "password"


def test_start_unknown_env_fails(sandboxed_settings: Settings) -> None:
    provider = FakeVNCProvider(port_factory=lambda: 1)
    svc = VNCService(sandboxed_settings, provider=provider)
    with pytest.raises(VNCError):
        svc.start("not_a_real_env", await_ready=True)


def test_start_replaces_previous_session(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    """Single-user: starting a new env tears down the old one."""
    provider = FakeVNCProvider(port_factory=lambda: echo_server.port)
    svc = VNCService(sandboxed_settings, provider=provider)
    first = svc.start("moodle_env", await_ready=True)
    second = svc.start("moodle_env", await_ready=True)
    assert first.id != second.id
    assert svc.current() is not None
    assert svc.current().id == second.id


def test_reset_keeps_session(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    provider = FakeVNCProvider(port_factory=lambda: echo_server.port)
    svc = VNCService(sandboxed_settings, provider=provider)
    s = svc.start("moodle_env", await_ready=True)
    refreshed = svc.reset(s.id, await_ready=True)
    assert refreshed.id == s.id
    assert refreshed.status == "running"


def test_stop_clears_active(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    provider = FakeVNCProvider(port_factory=lambda: echo_server.port)
    svc = VNCService(sandboxed_settings, provider=provider)
    s = svc.start("moodle_env", await_ready=True)
    svc.stop(s.id)
    assert svc.current() is None


def test_start_default_is_async_returns_starting(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    """Default start() returns immediately with status='starting' so the
    HTTP endpoint can respond fast even when the env boot takes minutes.
    Status flips to 'running' once the background boot completes.
    """
    import threading
    import time

    # A provider that holds the boot until we release it — proves the
    # foreground call returned before booting completed.
    release = threading.Event()

    class SlowProvider:
        def __init__(self, port: int) -> None:
            self._port = port

        def start(self, env_dir: str):
            release.wait(timeout=5)
            return ("127.0.0.1", self._port, "password", object())

        def reset(self, backend_handle):
            return ("127.0.0.1", self._port, "password")

        def stop(self, backend_handle):
            return

    svc = VNCService(sandboxed_settings, provider=SlowProvider(echo_server.port))
    session = svc.start("moodle_env")  # no await_ready
    assert session.status == "starting", "start() must return before boot completes"
    assert session.vnc_port == 0, "vnc_port not populated until boot finishes"

    release.set()
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if session.status == "running":
            break
        time.sleep(0.05)
    assert session.status == "running"
    assert session.vnc_port == echo_server.port


def test_start_async_failure_marks_failed(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    """If the background boot raises, the session ends up status='failed'
    with last_error populated — start() itself still returned cleanly
    with status='starting'; subsequent polling surfaces the failure.
    """
    import threading
    import time

    # Block the boot until the test releases it; that way the
    # 'starting' assertion has no race with the background thread.
    release = threading.Event()

    class BadProvider:
        def start(self, env_dir: str):
            release.wait(timeout=5)
            raise RuntimeError("env refused to boot — gvproxy unavailable")

        def reset(self, backend_handle):
            raise RuntimeError("n/a")

        def stop(self, backend_handle):
            return

    svc = VNCService(sandboxed_settings, provider=BadProvider())
    session = svc.start("moodle_env")  # async, so no exception here
    assert session.status == "starting"

    release.set()
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if session.status == "failed":
            break
        time.sleep(0.05)
    assert session.status == "failed"
    assert "gvproxy unavailable" in (session.last_error or "")


# ----------------------------------------------------------------------
# Proxy — drives bytes through FastAPI's WebSocket TestClient
# ----------------------------------------------------------------------


def test_ws_proxy_echoes_bytes(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    from extras.research.expert_console.server.app import create_app
    from extras.research.expert_console.server.config import get_settings

    provider = FakeVNCProvider(port_factory=lambda: echo_server.port)
    app = create_app(
        settings=sandboxed_settings,
        skip_runtime_validation=True,
        vnc_provider=provider,
    )
    app.dependency_overrides[get_settings] = lambda: sandboxed_settings
    with TestClient(app) as client:
        resp = client.post(
            "/api/vnc/start?await_ready=true",
            json={"env_dir": "moodle_env"},
        )
        assert resp.status_code == 200, resp.text
        session_id = resp.json()["id"]
        with client.websocket_connect(f"/api/vnc/ws/{session_id}") as ws:
            ws.send_bytes(b"hello vnc")
            received = ws.receive_bytes()
            assert received == b"hello vnc"


def test_api_vnc_lifecycle(
    sandboxed_settings: Settings, echo_server: EchoServer
) -> None:
    from extras.research.expert_console.server.app import create_app
    from extras.research.expert_console.server.config import get_settings

    provider = FakeVNCProvider(port_factory=lambda: echo_server.port)
    app = create_app(
        settings=sandboxed_settings,
        skip_runtime_validation=True,
        vnc_provider=provider,
    )
    app.dependency_overrides[get_settings] = lambda: sandboxed_settings
    with TestClient(app) as client:
        # No active session up front
        assert client.get("/api/vnc").json()["active"] is False
        # Start synchronously so we can immediately assert running state.
        start = client.post(
            "/api/vnc/start?await_ready=true",
            json={"env_dir": "moodle_env"},
        ).json()
        sid = start["id"]
        assert start["status"] == "running"
        active = client.get("/api/vnc").json()
        assert active["active"] is True
        assert active["id"] == sid
        # Reset (also await)
        reset = client.post(
            f"/api/vnc/{sid}/reset?await_ready=true"
        ).json()
        assert reset["id"] == sid
        assert reset["status"] == "running"
        # Stop
        stop = client.post(f"/api/vnc/{sid}/stop").json()
        assert stop["stopped"] is True
        assert client.get("/api/vnc").json()["active"] is False
