from __future__ import annotations

import random
from typing import Any, Dict, Optional

import base64

from ...specs import EnvSpec
from .base import BaseRunner


class LocalRunner(BaseRunner):
    """A minimal local runner for smoke tests.

    Produces blank observations and no-ops on actions. Useful for validating the
    orchestration and API without external dependencies.
    """

    def __init__(self, spec: EnvSpec):
        super().__init__(spec)
        self._running = False
        self._w = 640
        self._h = 480

    def start(self, seed: Optional[int] = None) -> None:
        random.seed(seed)
        self._running = True

    def stop(self) -> None:
        self._running = False

    def run_reset(self, reset_script: str, seed: Optional[int] = None) -> None:
        # No-op in local mode
        return None

    def run_task_init(self, init_script: str) -> None:
        # No-op in local mode
        return None

    def inject_action(self, action: Dict[str, Any]) -> None:
        # No-op, just accept the dict
        return None

    def capture_observation(self) -> Dict[str, Any]:
        # Return a trivial black frame and empty audio buffer
        obs: Dict[str, Any] = {}
        obs["screen"] = {
            "shape": (self._h, self._w, 3),
            "format": "rgb",
            "data_b64": None,  # intentionally omitted to avoid large payloads
        }
        obs["audio"] = {
            "rate": 16000,
            "channels": 1,
            "num_samples": 0,
        }
        return obs

    # Additional APIs (no-op/fallbacks)
    def exec(
        self,
        cmd: str,
        env: Optional[Dict[str, str]] = None,
        user: Optional[str] = None,
        use_pty: bool = True,
        timeout: int = 600,
    ) -> int:
        # use_pty accepted for API compatibility but ignored in local runner
        del cmd, env, user, use_pty, timeout
        return 0

    def exec_async(self, cmd: str, env: Optional[Dict[str, str]] = None, stdout=None, stderr=None):
        raise NotImplementedError("LocalRunner does not support async exec")

    def put_file(self, host_path) -> str:
        return str(host_path)

    def exec_capture(self, cmd: str) -> str:
        return ""

    def exec_capture_bytes(self, cmd: str) -> bytes:
        return b""

    def capture_screenshot(self, host_path) -> bool:
        # Not supported in local mode
        return False

    def capture_audio_raw(self, duration_sec: float, rate: int, channels: int) -> bytes:
        return b""

    def copy_to(self, host_src: str, container_dst: str) -> None:
        return None

    def copy_from(self, container_src: str, host_dst: str) -> None:
        return None
