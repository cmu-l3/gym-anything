"""VNC proxy + env lifecycle for the expert console.

The console runs a single user, so we manage at most one live env per
process. Lifecycle:

  start(env_dir) -> session_id
       │
       ▼  (frontend opens WS to /api/vnc/ws/{session_id})
  proxy WebSocket <-> TCP(localhost, vnc_port)
       │
       ▼
  reset() | stop()

The actual env boot is delegated to a `VNCEnvProvider` protocol. The
production implementation calls `gym_anything.from_config(...).reset()`
and reads `SessionInfo.vnc_port`; tests inject a fake provider that
points at any TCP port (an echo server in the proxy tests).
"""

from __future__ import annotations

import asyncio
import logging
import socket
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Protocol

from ..config import Settings


logger = logging.getLogger("expert_console.vnc")


# ----------------------------------------------------------------------
# Result types
# ----------------------------------------------------------------------


@dataclass
class VNCSession:
    id: str
    env_dir: str
    vnc_host: str
    vnc_port: int
    started_at: datetime
    status: str  # "starting" | "running" | "stopping" | "stopped" | "failed"
    vnc_password: str | None = None
    backend_env: Any | None = field(default=None, repr=False)
    last_error: str | None = None

    def to_public(self) -> dict:
        return {
            "id": self.id,
            "env_dir": self.env_dir,
            "vnc_host": self.vnc_host,
            "vnc_port": self.vnc_port,
            "vnc_password": self.vnc_password,
            "started_at": self.started_at.isoformat(),
            "status": self.status,
            "last_error": self.last_error,
        }


class VNCError(RuntimeError):
    """Raised on invalid VNC operations."""


# ----------------------------------------------------------------------
# Provider protocol
# ----------------------------------------------------------------------


class VNCEnvProvider(Protocol):
    def start(self, env_dir: str) -> tuple[str, int, str | None, Any]:
        """Start the env. Returns (host, port, password, backend_handle)."""

    def reset(self, backend_handle: Any) -> tuple[str, int, str | None]:
        """Reset the env. Returns the (possibly-new) (host, port, password)."""

    def stop(self, backend_handle: Any) -> None:
        """Stop the env."""


class GymAnythingVNCProvider:
    """Production provider — uses `gym_anything.from_config()`.

    Caching is requested only when the selected runner actually supports
    it (Docker, QEMU+Apptainer, etc.). Runners without caching support
    (e.g. AVF on Apple Silicon) get a plain `reset()` — not a fallback,
    just capability dispatch.
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def _reset_env(self, env) -> None:
        runner = getattr(env, "_runner", None)
        supports_caching = bool(
            runner and getattr(runner, "supports_checkpoint_caching", lambda: False)()
        )
        if supports_caching:
            env.reset(use_cache=True, cache_level="default")
        else:
            env.reset()

    def start(self, env_dir: str) -> tuple[str, int, str | None, Any]:
        from gym_anything import from_config

        env_path = self.settings.environments_dir / env_dir
        if not env_path.is_dir():
            raise VNCError(f"Unknown env_dir: {env_dir}")
        env = from_config(str(env_path))
        try:
            self._reset_env(env)
        except Exception as exc:
            try:
                env.close()
            except Exception:
                logger.exception("Closing env after failed reset")
            raise VNCError(f"Failed to start env {env_dir}: {exc}") from exc
        info = env.get_session_info()
        if info is None or info.vnc_port is None:
            try:
                env.close()
            except Exception:
                logger.exception("Closing env after no VNC port available")
            raise VNCError(
                f"Env {env_dir} did not expose a VNC port. "
                f"Check env.json `vnc.enable` and runner support."
            )
        return ("127.0.0.1", info.vnc_port, info.vnc_password, env)

    def reset(self, backend_handle: Any) -> tuple[str, int, str | None]:
        env = backend_handle
        self._reset_env(env)
        info = env.get_session_info()
        if info is None or info.vnc_port is None:
            raise VNCError("Env reset did not produce a VNC port.")
        return ("127.0.0.1", info.vnc_port, info.vnc_password)

    def stop(self, backend_handle: Any) -> None:
        try:
            backend_handle.close()
        except Exception:
            logger.exception("Error closing env during stop")
            raise


# ----------------------------------------------------------------------
# Service
# ----------------------------------------------------------------------


class VNCService:
    def __init__(
        self,
        settings: Settings,
        *,
        provider: VNCEnvProvider | None = None,
    ) -> None:
        self.settings = settings
        self._provider: VNCEnvProvider | None = provider
        self._lock = threading.Lock()
        self._sessions: dict[str, VNCSession] = {}

    @property
    def provider(self) -> VNCEnvProvider:
        if self._provider is None:
            self._provider = GymAnythingVNCProvider(self.settings)
        return self._provider

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self, env_dir: str, *, await_ready: bool = False) -> VNCSession:
        """Start an env asynchronously. Returns immediately with status
        `starting`; a background thread does the actual `env.reset()`
        (which can take several minutes — Odoo etc. boot pre_start +
        post_start hooks). Status flips to `running` on success or
        `failed` on error.

        `await_ready=True` blocks until the boot finishes — used by the
        backend test suite so tests don't need to poll.
        """
        # Single-user model: tear down any previously-running session first.
        with self._lock:
            existing = self._active_session()
        if existing is not None:
            self.stop(existing.id)

        env_path = self.settings.environments_dir / env_dir
        if not env_path.is_dir():
            raise VNCError(f"Unknown env_dir: {env_dir}")
        session_id = uuid.uuid4().hex
        session = VNCSession(
            id=session_id,
            env_dir=env_dir,
            vnc_host="127.0.0.1",
            vnc_port=0,
            started_at=datetime.now(timezone.utc),
            status="starting",
        )
        ready = threading.Event()
        with self._lock:
            self._sessions[session_id] = session

        def _boot() -> None:
            try:
                host, port, password, backend = self.provider.start(env_dir)
            except Exception as exc:
                session.status = "failed"
                session.last_error = str(exc)
                logger.exception("VNC boot failed for env %s", env_dir)
                ready.set()
                return
            session.vnc_host = host
            session.vnc_port = port
            session.vnc_password = password
            session.backend_env = backend
            session.status = "running"
            ready.set()

        thread = threading.Thread(
            target=_boot, daemon=True, name=f"vnc-boot-{session_id[:8]}"
        )
        thread.start()

        if await_ready:
            ready.wait()
            if session.status == "failed":
                raise VNCError(
                    f"Failed to start env {env_dir}: {session.last_error}"
                )
        return session

    def reset(self, session_id: str, *, await_ready: bool = False) -> VNCSession:
        session = self._require(session_id)
        if session.backend_env is None:
            raise VNCError(f"Session {session_id} has no backend handle.")
        ready = threading.Event()

        def _do_reset() -> None:
            try:
                host, port, password = self.provider.reset(session.backend_env)
            except Exception as exc:
                session.status = "failed"
                session.last_error = str(exc)
                logger.exception("VNC reset failed for session %s", session_id)
                ready.set()
                return
            session.vnc_host = host
            session.vnc_port = port
            session.vnc_password = password
            session.status = "running"
            ready.set()

        # Mark as starting again so the UI polling shows the transition.
        session.status = "starting"
        thread = threading.Thread(
            target=_do_reset, daemon=True, name=f"vnc-reset-{session_id[:8]}"
        )
        thread.start()

        if await_ready:
            ready.wait()
            if session.status == "failed":
                raise VNCError(f"Reset failed: {session.last_error}")
        return session

    def stop(self, session_id: str) -> None:
        with self._lock:
            session = self._sessions.get(session_id)
        if session is None:
            raise VNCError(f"Unknown VNC session: {session_id}")
        session.status = "stopping"
        try:
            if session.backend_env is not None:
                self.provider.stop(session.backend_env)
        finally:
            session.status = "stopped"
            session.backend_env = None
            with self._lock:
                self._sessions.pop(session_id, None)

    def get(self, session_id: str) -> VNCSession:
        return self._require(session_id)

    def current(self) -> VNCSession | None:
        with self._lock:
            return self._active_session()

    # ------------------------------------------------------------------
    # Proxy
    # ------------------------------------------------------------------

    async def proxy(
        self,
        session_id: str,
        websocket,
    ) -> None:
        """Pump bytes between the WS and the VNC TCP port."""
        from starlette.websockets import WebSocketDisconnect

        session = self._require(session_id)
        if session.status != "running":
            await websocket.close(code=4400)
            raise VNCError(f"VNC session {session_id} not running.")

        try:
            reader, writer = await asyncio.open_connection(
                session.vnc_host, session.vnc_port
            )
        except OSError as exc:
            await websocket.close(code=4503)
            raise VNCError(
                f"Could not connect to VNC at {session.vnc_host}:{session.vnc_port}: {exc}"
            ) from exc

        async def ws_to_tcp() -> None:
            try:
                while True:
                    data = await websocket.receive_bytes()
                    writer.write(data)
                    await writer.drain()
            except WebSocketDisconnect:
                pass
            except Exception:
                logger.exception("ws->tcp pump error")

        async def tcp_to_ws() -> None:
            try:
                while True:
                    chunk = await reader.read(8192)
                    if not chunk:
                        return
                    await websocket.send_bytes(chunk)
            except Exception:
                logger.exception("tcp->ws pump error")

        try:
            await asyncio.wait(
                {asyncio.create_task(ws_to_tcp()), asyncio.create_task(tcp_to_ws())},
                return_when=asyncio.FIRST_COMPLETED,
            )
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
            try:
                await websocket.close()
            except Exception:
                pass

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def _require(self, session_id: str) -> VNCSession:
        with self._lock:
            s = self._sessions.get(session_id)
        if s is None:
            raise VNCError(f"Unknown VNC session: {session_id}")
        return s

    def _active_session(self) -> VNCSession | None:
        for s in self._sessions.values():
            if s.status in {"starting", "running"}:
                return s
        return None


# ----------------------------------------------------------------------
# Fake provider — for tests and offline development
# ----------------------------------------------------------------------


class FakeVNCProvider:
    """Pretends to manage a VNC session. The `port_factory` returns
    the TCP port to advertise (tests typically pass an echo server's
    bound port).
    """

    def __init__(self, port_factory: "callable[[], int]") -> None:
        self._port_factory = port_factory
        self._reset_count = 0

    def start(self, env_dir: str) -> tuple[str, int, str | None, Any]:
        port = self._port_factory()
        return ("127.0.0.1", port, "password", object())

    def reset(self, backend_handle: Any) -> tuple[str, int, str | None]:
        self._reset_count += 1
        return ("127.0.0.1", self._port_factory(), "password")

    def stop(self, backend_handle: Any) -> None:
        return


# ----------------------------------------------------------------------
# Test helper — TCP echo server
# ----------------------------------------------------------------------


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


__all__ = [
    "VNCService",
    "VNCError",
    "VNCSession",
    "VNCEnvProvider",
    "GymAnythingVNCProvider",
    "FakeVNCProvider",
    "free_port",
]
