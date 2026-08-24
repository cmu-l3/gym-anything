"""Shared machinery for running existing CLI coding harnesses (Claude Code,
Codex CLI, ...) as gym-anything computer-use agents.

Design (see the agents docs): the CLI never runs inside the task VM. It runs
in a throwaway, GUI-less isolated sandbox (apptainer or docker, see
``agent_sandbox.py``) and uses an in-process HTTP *action gateway* as its task
control interface. The env is a separate VM, so the CLI has no filesystem path
into it.

The gateway speaks the same text action vocabulary the other agents use
(``agents/shared/qwen_computer_use.py``): the CLI sends one action as a JSON
string, the gateway parses it, injects it through ``env.step()``, and captures
the response through an independent observation lane. Live modes return one
instantaneous frame; paused mode may return a chronological frame window.
Inside the container a tiny ``act`` wrapper POSTs the command and writes the
returned frame(s) to files the CLI then views. No MCP, no per-CLI protocol.

State-changing actions flow through ``env.step()`` so step limits, timeouts,
``traj.jsonl``, frame capture, and verification stay on the normal
``GymAnythingEnv`` path. Observation-only screenshot requests use
``env.capture_observation()`` and do not consume the action budget. The
gateway's per-command log is the authoritative agent transcript.
"""

from __future__ import annotations

import base64
import heapq
import json
import logging
import math
import os
import secrets
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from pathlib import Path
from typing import Any, Callable, Optional

from PIL import Image

from agents.shared.agent_sandbox import AgentSandbox, SandboxSpec, select_sandbox
from agents.shared.qwen_computer_use import parse_qwen3vl_response
from agents.shared.temporal_modes import (
    scheduled_execution_enabled,
    timestamps_enabled,
    validate_temporal_mode,
)

logger = logging.getLogger(__name__)


# The single action the CLI can never issue meaningfully but might try; keep
# the list here so both the prompt and the gateway agree.
_TERMINATE_ACTIONS = {"terminate", "done", "finish"}

# The screenshot the CLI's model sees is downscaled to fit this longest side.
# Coding CLIs (Claude Code, Codex) silently downscale large images before the
# model sees them and then report pixel coordinates in that reduced space; if
# we serve full-res frames, every click lands short. So WE control the display
# size: serve frames at this size, take pixel coords in it, and scale back to
# the env's native resolution. 1280 keeps the image under model auto-downscale
# thresholds so what the model sees is 1:1 with what we sent.
_DISPLAY_MAX_LONG_SIDE = 1280


@dataclass(order=True)
class _ActionJob:
    """One action waiting for the gateway's single injection lane."""

    target_wall_ms: float
    sequence: int
    env_actions: list[dict[str, Any]] = field(compare=False)


def _obs_png_bytes(
    obs: dict[str, Any],
    fetch_path: Optional[Callable[[str], str]] = None,
) -> Optional[bytes]:
    """Extract the observation screenshot as raw PNG bytes, or None."""
    if not isinstance(obs, dict):
        return None
    screen = obs.get("screen") or {}
    if not isinstance(screen, dict):
        return None
    image = screen.get("image")
    if image is not None and hasattr(image, "save"):
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        return buffer.getvalue()
    if screen.get("png_b64"):
        try:
            return base64.b64decode(screen["png_b64"])
        except (ValueError, TypeError):
            return None
    path = screen.get("path")
    if path:
        local_path = str(path)
        if not os.path.exists(local_path) and fetch_path is not None:
            try:
                local_path = str(fetch_path(local_path))
            except Exception:
                logger.warning("Could not fetch remote observation frame %s", path, exc_info=True)
                return None
        if not os.path.exists(local_path):
            return None
        with open(local_path, "rb") as handle:
            return handle.read()
    return None


class ActionGateway:
    """Translate CLI action-command strings into ``env.step()`` calls.

    The HTTP surface is a thin wrapper; ``step_from_command`` is the testable
    core (no docker, no sockets). HTTP clients may issue concurrent requests.
    A priority queue serializes only action injection; scheduled waiting holds
    no lane lock. Observation capture is serialized separately and can overlap
    an action from another request.
    """

    def __init__(
        self,
        env: Any,
        resolution: tuple[int, int],
        max_steps: int,
        token: str,
        temporal_mode: str = "live",
    ):
        self.env = env
        self.width, self.height = resolution
        # Display size the model actually sees; coords come back in this space.
        scale = min(1.0, _DISPLAY_MAX_LONG_SIDE / max(self.width, self.height))
        self.display_w = max(1, round(self.width * scale))
        self.display_h = max(1, round(self.height * scale))
        # Model (display) pixels -> env (native) pixels.
        self.ratio_x = self.width / self.display_w
        self.ratio_y = self.height / self.display_h
        self.max_steps = max_steps
        self.token = token
        self.temporal_mode = validate_temporal_mode(temporal_mode)
        self.steps_taken = 0
        self.observations_served = 0
        self.transcript: list[dict[str, Any]] = []
        self._state_lock = threading.RLock()
        self._observation_lock = threading.Lock()
        self._action_condition = threading.Condition()
        self._action_jobs: list[_ActionJob] = []
        self._action_active = False
        self._next_action_sequence = 0
        self._actions_reserved = 0
        self._t0_ms: float | None = None
        self._last_frame_seen_s: float | None = None
        self._latency_log: list[float] = []
        self._server: Optional[ThreadingHTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    def _display_screenshots_b64(self, obs: dict[str, Any]) -> list[str]:
        """Return the mode's observation frame(s) at the display size."""
        frames = obs.get("frames") if isinstance(obs, dict) else None
        if isinstance(frames, list) and frames:
            if self.temporal_mode != "paused":
                frames = frames[-1:]
            observations = [
                {"screen": frame if isinstance(frame, dict) else {"path": frame}}
                for frame in frames
            ]
        else:
            observations = [obs]

        fetch_path = getattr(self.env, "fetch_path", None)
        encoded: list[str] = []
        for observation in observations:
            raw = _obs_png_bytes(observation, fetch_path=fetch_path)
            if raw is None:
                continue
            try:
                img = Image.open(BytesIO(raw))
                if img.size != (self.display_w, self.display_h):
                    img = img.resize((self.display_w, self.display_h))
                buffer = BytesIO()
                img.convert("RGB").save(buffer, format="PNG")
                encoded.append(base64.b64encode(buffer.getvalue()).decode("ascii"))
            except Exception:
                # Not a decodable image (e.g. a stub in tests): pass bytes through.
                encoded.append(base64.b64encode(raw).decode("ascii"))
        return encoded

    def _capture_manifest(self, obs: dict[str, Any]) -> dict[str, Any] | None:
        path = obs.get("capture_manifest") if isinstance(obs, dict) else None
        if not path:
            return None
        local_path = str(path)
        if not os.path.exists(local_path):
            fetch_path = getattr(self.env, "fetch_path", None)
            if fetch_path is None:
                return None
            try:
                local_path = str(fetch_path(local_path))
            except Exception:
                logger.warning("Could not fetch capture manifest %s", path, exc_info=True)
                return None
        try:
            with open(local_path, "r", encoding="utf-8") as handle:
                manifest = json.load(handle)
        except (OSError, json.JSONDecodeError):
            logger.warning("Could not read capture manifest %s", local_path, exc_info=True)
            return None
        return manifest if isinstance(manifest, dict) else None

    def _timing_payload(
        self,
        obs: dict[str, Any],
        *,
        action_receipt: dict[str, float | None] | None,
        capture_finished_wall_ms: float,
    ) -> dict[str, Any] | None:
        if not timestamps_enabled(self.temporal_mode):
            return None
        manifest = self._capture_manifest(obs)
        frame_wall_ms = capture_finished_wall_ms
        if manifest is not None:
            start = manifest.get("window_started_wall_ms")
            frames = manifest.get("frames") or []
            if start is not None and frames:
                frame_wall_ms = float(start) + float(frames[-1].get("offset_ms") or 0)

        with self._state_lock:
            if self._t0_ms is None:
                self._t0_ms = frame_wall_ms
            frame_s = round((frame_wall_ms - self._t0_ms) / 1000.0, 3)
            current_s = round(
                (time.time_ns() / 1_000_000 - self._t0_ms) / 1000.0,
                3,
            )
            payload: dict[str, Any] = {
                "frame_captured_at_s": frame_s,
                # Compatibility with the original timestamped-window contract.
                "screenshot_captured_at_s": [frame_s],
                # Keep response time distinct from frame time. Frame retrieval
                # and encoding may take long enough that the image timestamp is
                # already in the past when the caller chooses execute_at_s.
                "current_time_s": current_s,
            }
            if action_receipt is not None:
                executed_wall_ms = float(action_receipt["executed_wall_ms"])
                executed_s = round((executed_wall_ms - self._t0_ms) / 1000.0, 3)
                payload["action_executed_at_s"] = executed_s
                payload["previous_action_finished_executing_by_s"] = executed_s
                requested_execute_at_s = action_receipt.get("requested_execute_at_s")
                if requested_execute_at_s is not None:
                    payload["previous_action_requested_execute_at_s"] = (
                        requested_execute_at_s
                    )
                    payload["action_execution_lateness_s"] = round(
                        executed_s - float(requested_execute_at_s), 3
                    )
                observed_frame_s = action_receipt.get("observed_frame_s")
                if observed_frame_s is not None:
                    latency = round(executed_s - float(observed_frame_s), 3)
                    payload[
                        "seconds_between_your_last_screenshot_and_that_action_landing"
                    ] = latency
                    self._latency_log.append(latency)
                    payload["your_recent_observe_to_execute_latencies_s"] = (
                        self._latency_log[-8:]
                    )
            self._last_frame_seen_s = frame_s
        return payload

    def _screenshot_payload(
        self,
        obs: dict[str, Any],
        *,
        action_receipt: dict[str, float | None] | None = None,
        capture_finished_wall_ms: float,
    ) -> dict[str, Any]:
        screenshots = self._display_screenshots_b64(obs)
        with self._state_lock:
            observation_index = self.observations_served
            self.observations_served += 1
        payload = {
            "observation": observation_index,
            "screenshots_b64": screenshots,
            # Compatibility for callers that only understand a single frame.
            "screenshot_b64": screenshots[-1] if screenshots else None,
        }
        timing = self._timing_payload(
            obs,
            action_receipt=action_receipt,
            capture_finished_wall_ms=capture_finished_wall_ms,
        )
        if timing is not None:
            payload["timing"] = timing
        return payload

    def _capture_payload(
        self,
        *,
        action_receipt: dict[str, float | None] | None = None,
    ) -> dict[str, Any]:
        """Capture through the observation lane, independently of injection."""
        with self._observation_lock:
            obs = self.env.capture_observation()
            capture_finished_wall_ms = time.time_ns() / 1_000_000
            return self._screenshot_payload(
                obs,
                action_receipt=action_receipt,
                capture_finished_wall_ms=capture_finished_wall_ms,
            )

    # --- action translation ------------------------------------------------

    def _env_actions_for(
        self, command: str
    ) -> tuple[list[dict[str, Any]], bool, bool, float | None, Optional[str]]:
        """Return (actions, terminal, observation, execute_at_s, error).

        Reuses ``parse_qwen3vl_response`` (single source of truth for the
        action vocabulary) by wrapping the raw action JSON in the tool-call
        envelope the parser expects. The model gives pixel coordinates in the
        display-sized screenshot it was shown; the parser's ``scale_dims``
        ratio maps those display pixels back to the env's native resolution.
        """
        try:
            action_json = json.loads(command)
        except (json.JSONDecodeError, TypeError) as exc:
            return [], False, False, None, f"invalid action JSON: {exc}"

        if not isinstance(action_json, dict) or "action" not in action_json:
            return [], False, False, None, "action JSON must be an object with an 'action' key"
        if not isinstance(action_json["action"], str):
            return [], False, False, None, "the 'action' value must be a string"

        raw_execute_at_s = action_json.pop("execute_at_s", None)
        execute_at_s: float | None = None
        if raw_execute_at_s is not None:
            if not scheduled_execution_enabled(self.temporal_mode):
                return (
                    [],
                    False,
                    False,
                    None,
                    "execute_at_s is available only in live_timestamped_execution mode",
                )
            try:
                execute_at_s = float(raw_execute_at_s)
            except (TypeError, ValueError):
                return [], False, False, None, "execute_at_s must be a number"
            if not math.isfinite(execute_at_s) or execute_at_s < 0:
                return (
                    [],
                    False,
                    False,
                    None,
                    "execute_at_s must be finite and non-negative",
                )

        name = action_json["action"].lower()
        if name == "screenshot":
            if execute_at_s is not None:
                return [], False, False, None, "a screenshot cannot be scheduled"
            return [], False, True, None, None
        if name in _TERMINATE_ACTIONS:
            if execute_at_s is not None:
                return [], False, False, None, "termination cannot be scheduled"
            return [], True, False, None, None

        synthetic = (
            '<tool_call>{"name": "computer_use", "arguments": '
            + json.dumps(action_json)
            + "}</tool_call>"
        )
        parsed = parse_qwen3vl_response(
            synthetic,
            scale_dims=True,
            scale_dims_ratio=(self.ratio_x, self.ratio_y),
        )
        meta = parsed["metadata"]
        if meta.get("parse_error"):
            return [], False, False, None, f"could not parse action: {meta.get('conclusion')}"
        env_actions = parsed["actions"]
        if meta.get("wait_time") is not None:
            env_actions = [{"action": "wait", "time": meta["wait_time"]}]
        if execute_at_s is not None:
            with self._state_lock:
                has_clock_origin = self._t0_ms is not None
            if not has_clock_origin:
                return (
                    [],
                    False,
                    False,
                    None,
                    "request a screenshot before using execute_at_s",
                )
        return env_actions, bool(meta.get("is_terminal")), False, execute_at_s, None

    def step_from_command(self, command: str) -> dict[str, Any]:
        """Execute one action through independent action/observation lanes."""
        with self._state_lock:
            exhausted = self.steps_taken + self._actions_reserved >= self.max_steps
            step = self.steps_taken
        if exhausted:
            return {
                "step": step,
                "budget_remaining": 0,
                "done": True,
                "error": "step budget exhausted",
                **self._capture_payload(),
            }

        env_actions, is_terminal, is_observation, execute_at_s, error = (
            self._env_actions_for(command)
        )

        if error is not None:
            # Do not consume budget on a malformed command; let the model retry.
            with self._state_lock:
                step = self.steps_taken
                budget_remaining = max(
                    0, self.max_steps - self.steps_taken - self._actions_reserved
                )
                self.transcript.append(
                    {"step": step, "command": command, "error": error}
                )
            return {
                "step": step,
                "budget_remaining": budget_remaining,
                "done": False,
                "error": error,
                **self._capture_payload(),
            }

        if is_observation:
            with self._state_lock:
                step = self.steps_taken
                budget_remaining = max(
                    0, self.max_steps - self.steps_taken - self._actions_reserved
                )
                self.transcript.append(
                    {
                        "step": step,
                        "command": command,
                        "env_actions": [],
                        "observation_only": True,
                    }
                )
            return {
                "step": step,
                "budget_remaining": budget_remaining,
                "done": False,
                "error": None,
                **self._capture_payload(),
            }

        with self._state_lock:
            if self.steps_taken + self._actions_reserved >= self.max_steps:
                reservation_failed = True
                step = self.steps_taken
            else:
                reservation_failed = False
                self._actions_reserved += 1
                observed_frame_s = self._last_frame_seen_s
                if execute_at_s is None:
                    target_wall_ms = time.time_ns() / 1_000_000
                else:
                    target_wall_ms = float(self._t0_ms) + execute_at_s * 1000.0
        if reservation_failed:
            return {
                "step": step,
                "budget_remaining": 0,
                "done": True,
                "error": "step budget exhausted",
                **self._capture_payload(),
            }

        try:
            done, executed_wall_ms = self._execute_action(
                env_actions,
                target_wall_ms=target_wall_ms,
            )
        except Exception:
            with self._state_lock:
                self._actions_reserved -= 1
            raise

        action_receipt: dict[str, float | None] = {
            "executed_wall_ms": executed_wall_ms,
            "requested_execute_at_s": execute_at_s,
            "observed_frame_s": observed_frame_s,
        }
        with self._state_lock:
            self._actions_reserved -= 1
            self.steps_taken += 1
            step = self.steps_taken
            budget_remaining = max(
                0, self.max_steps - self.steps_taken - self._actions_reserved
            )
            response_done = bool(done) or is_terminal or step >= self.max_steps
            self.transcript.append(
                {
                    "step": step,
                    "command": command,
                    "env_actions": env_actions,
                    "requested_execute_at_s": execute_at_s,
                    "action_executed_wall_ms": executed_wall_ms,
                    "terminal_requested": is_terminal,
                    "env_done": bool(done),
                }
            )
        return {
            "step": step,
            "budget_remaining": budget_remaining,
            "done": response_done,
            "error": None,
            **self._capture_payload(action_receipt=action_receipt),
        }

    def _execute_action(
        self,
        env_actions: list[dict[str, Any]],
        *,
        target_wall_ms: float,
    ) -> tuple[bool, float]:
        """Wait without the lane, then inject one action and return its receipt."""
        with self._action_condition:
            job = _ActionJob(
                target_wall_ms=target_wall_ms,
                sequence=self._next_action_sequence,
                env_actions=env_actions,
            )
            self._next_action_sequence += 1
            heapq.heappush(self._action_jobs, job)
            self._action_condition.notify_all()
            while self._action_active or self._action_jobs[0] is not job:
                self._action_condition.wait()
            while True:
                remaining_s = (
                    job.target_wall_ms - time.time_ns() / 1_000_000
                ) / 1000.0
                if remaining_s <= 0:
                    break
                self._action_condition.wait(timeout=remaining_s)
                if self._action_active or self._action_jobs[0] is not job:
                    while self._action_active or self._action_jobs[0] is not job:
                        self._action_condition.wait()
            heapq.heappop(self._action_jobs)
            self._action_active = True

        try:
            _obs, _reward, done, _info = self.env.step(
                job.env_actions,
                capture_observation=False,
                settle_after_actions=False,
            )
            executed_wall_ms = time.time_ns() / 1_000_000
            return bool(done), executed_wall_ms
        finally:
            with self._action_condition:
                self._action_active = False
                self._action_condition.notify_all()

    # --- HTTP server --------------------------------------------------------

    def start(self, host: str = "0.0.0.0") -> int:
        """Start the gateway on an ephemeral port; return the port."""
        gateway = self

        class _Handler(BaseHTTPRequestHandler):
            def log_message(self, *args: Any) -> None:  # silence default logging
                pass

            def do_POST(self) -> None:
                if self.headers.get("X-Gateway-Token") != gateway.token:
                    self.send_response(403)
                    self.end_headers()
                    return
                length = int(self.headers.get("Content-Length", 0))
                try:
                    payload = json.loads(self.rfile.read(length) or b"{}")
                    command = payload["command"]
                except (json.JSONDecodeError, KeyError, ValueError) as exc:
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": str(exc)}).encode())
                    return
                try:
                    result = gateway.step_from_command(command)
                except Exception as exc:  # keep the CLI alive on env hiccups
                    logger.exception("gateway step failed")
                    result = {"error": f"gateway error: {exc}", "done": False}
                body = json.dumps(result).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self._server = ThreadingHTTPServer((host, 0), _Handler)
        port = self._server.server_address[1]
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        logger.info("Action gateway listening on %s:%d", host, port)
        return port

    def stop(self) -> None:
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
            self._server = None


def build_harness_prompt(
    task_description: str,
    resolution: tuple[int, int],
    max_steps: int,
    temporal_mode: str = "live",
) -> str:
    """Instruction telling the CLI how to drive the computer through the gateway."""
    temporal_mode = validate_temporal_mode(temporal_mode)
    width, height = resolution
    response_timing = (
        ', "timing": object|null' if timestamps_enabled(temporal_mode) else ""
    )
    if temporal_mode == "paused":
        temporal_instructions = (
            "The task clock is paused while you reason and while your action is delivered. "
            "It advances only through each configured observation window. After the "
            "window completes, the task freezes on the final returned frame; your next "
            "action is applied to that final frame's state."
        )
    elif temporal_mode == "live":
        temporal_instructions = (
            "The task keeps moving while you reason and while actions are delivered. "
            "The API does not provide clock timestamps in this mode."
        )
    else:
        temporal_instructions = (
            "The task keeps moving while you reason and while actions are delivered. "
            "Each response includes `timing.frame_captured_at_s` and "
            "`timing.current_time_s` (the clock near response time); an action "
            "response also includes its "
            "`timing.action_executed_at_s` receipt and your recent "
            "observe-to-execute latency."
        )
        if scheduled_execution_enabled(temporal_mode):
            temporal_instructions += (
                " A mouse or keyboard action may include optional `execute_at_s`, an "
                "absolute time on the `current_time_s` clock. Omit it for immediate "
                "execution; a time that has passed executes immediately."
            )
    return f"""You are operating a remote computer to accomplish a task. You CANNOT \
see or touch this computer directly. The authenticated HTTP action gateway \
described below is your task-control interface.

You may use this API from any language and organize your work however you \
choose: Python functions or programs, JavaScript, shell commands, loops, OCR, \
computer-vision libraries, timing logic, or one command at a time are all \
allowed. `act` is installed on PATH as an optional convenience wrapper, not as \
a restriction on how you solve the task.

HTTP contract:
- URL: the `GATEWAY_URL` environment variable
- Method: POST
- Headers: `Content-Type: application/json` and `X-Gateway-Token` set to the \
  `GATEWAY_TOKEN` environment variable
- Request body: `{{"command": "<JSON-encoded action object>"}}`
- Response body: `{{"observation": int, "screenshots_b64": [str, ...], \
  "screenshot_b64": str|null, "step": int, "budget_remaining": int, \
  "done": bool, "error": str|null{response_timing}}}`

Temporal mode: `{temporal_mode}`. {temporal_instructions}

Here is a complete Python client. Each call saves every returned frame and \
returns both the response metadata and the chronological paths:

```python
import base64
import json
import os
import urllib.request
from pathlib import Path

def computer(action):
    request = urllib.request.Request(
        os.environ["GATEWAY_URL"],
        data=json.dumps({{"command": json.dumps(action)}}).encode(),
        headers={{
            "Content-Type": "application/json",
            "X-Gateway-Token": os.environ["GATEWAY_TOKEN"],
        }},
    )
    response = json.load(urllib.request.urlopen(request, timeout=180))
    paths = []
    for index, encoded in enumerate(response.get("screenshots_b64") or []):
        path = Path("obs") / (
            "observation_%04d_frame_%03d.png"
            % (response["observation"], index)
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(base64.b64decode(encoded))
        paths.append(str(path))
    return response, paths

response, paths = computer({{"action": "screenshot"}})
print(response["budget_remaining"], paths)
```

The equivalent convenience-wrapper calls are:

    act '{{"action": "screenshot"}}'
    act '{{"action": "left_click", "coordinate": [960, 540]}}'
    act '{{"action": "type", "text": "hello"}}'

Every response contains screenshot data captured after the action receipt. \
Live modes return exactly one instantaneous frame per request. Paused mode may \
return multiple chronological frames from its configured observation window. \
You may inspect or transform the images using any method. Start by requesting \
a screenshot to see the screen.

Coordinates are PIXELS in the screenshot image you view, which is exactly \
{width}x{height}: [0,0] is the top-left corner and [{width},{height}] is the \
bottom-right. Read the pixel position of your target directly off the \
screenshot. Windows may be small and not maximized, so aim at the center of \
the exact element (menu label, button, field) you want.

Available actions (the JSON `action` field):
- screenshot                                        — just observe
- left_click / right_click / double_click / triple_click, with "coordinate": [x, y]
- mouse_move, with "coordinate": [x, y]
- drag, with "coordinate": [x1, y1] and "coordinate2": [x2, y2]
- type, with "text": "...", optional "enter": true, optional "clear": true
- key, with "keys": ["ctrl", "s"]           — chord of held-then-released keys
- scroll, with "coordinate": [x, y] and "pixels": <negative up / positive down>
- wait, with "time": <seconds>
- terminate, with "status": "success"       — when the task is fully done

Rules:
- You have at most {max_steps} actions. Each non-observation gateway call spends one.
- All computer observations and actions must pass through the gateway. Do not \
  connect to the task VM, use SSH or VNC, access its filesystem, call its \
  services, or otherwise bypass the gateway. How you use the gateway is up to you.
- Stop sending actions if a response has `done: true`.
- When the task is fully complete, send `{{"action": "terminate", \
"status": "success"}}` through the gateway and stop.

Task:
{task_description}
"""


_ACT_SCRIPT = r"""#!/usr/bin/env python3
import sys, os, json, base64, urllib.request
if len(sys.argv) < 2:
    print("usage: act '<json action>'", file=sys.stderr); sys.exit(2)
command = sys.argv[1]
data = json.dumps({"command": command}).encode()
req = urllib.request.Request(
    os.environ["GATEWAY_URL"],
    data=data,
    headers={"Content-Type": "application/json",
             "X-Gateway-Token": os.environ.get("GATEWAY_TOKEN", "")},
)
try:
    resp = json.load(urllib.request.urlopen(req, timeout=180))
except Exception as exc:
    print(f"act: gateway request failed: {exc}", file=sys.stderr); sys.exit(1)
screenshots = resp.get("screenshots_b64") or []
if not screenshots and resp.get("screenshot_b64"):
    screenshots = [resp["screenshot_b64"]]
if screenshots:
    os.makedirs("obs", exist_ok=True)
    paths = []
    observation = int(resp.get("observation", resp.get("step", 0)))
    for index, screenshot in enumerate(screenshots):
        path = f"obs/observation_{observation:04d}_frame_{index:03d}.png"
        with open(path, "wb") as fh:
            fh.write(base64.b64decode(screenshot))
        paths.append(path)
    print(f"screenshots ({len(paths)} chronological frame(s); view all before acting):")
    for path in paths:
        print(f"  {path}")
if resp.get("error"):
    print(f"error: {resp['error']}")
if resp.get("timing") is not None:
    print("timing: " + json.dumps(resp["timing"], sort_keys=True))
print(f"budget_remaining: {resp.get('budget_remaining')}")
if resp.get("done"):
    print("EPISODE DONE: no further actions will be executed.")
"""


# The scratch image is built by the sandbox backend (agent_sandbox.py); the
# per-agent bits (base image, CLI install line, invocation) live on the agent
# subclasses. This module owns only the gateway, the prompt, and the `act`
# script above.


class CliHarnessAgent:
    """Base for agents that delegate the episode to an external CLI harness.

    Autonomous agents do not implement ``step()``. The evaluation loop calls
    ``run_episode(env, task_description)`` once; inside it the CLI drives the
    env through the action gateway, from inside an isolated sandbox
    (``agent_sandbox.py``). Subclasses supply the scratch image's base + CLI
    install line, the container environment, and the CLI invocation.
    """

    autonomous = True

    # Subclasses override these.
    sandbox_name: str = "cli"
    sandbox_base_image: str = "node:22-slim"
    sandbox_install: str = ""

    def __init__(self, agent_args: Optional[dict[str, Any]] = None, verbose: bool = False, debug: bool = False, **kwargs: Any):
        self.agent_args = agent_args or {}
        self.verbose = verbose
        self.debug = debug
        self.model = self.agent_args.get("model")
        self.temporal_mode = validate_temporal_mode(
            self.agent_args.get("temporal_mode")
        )
        self.timeout_sec = int(self.agent_args.get("timeout_sec", 3600))
        self.max_steps_override = self.agent_args.get("max_steps")
        self.done = False
        self.step_idx = -1
        self.display_resolution: tuple[int, int] = (1920, 1080)
        self.save_path: Optional[str] = None
        self.task_description: str = ""
        self._transcript: list[dict[str, Any]] = []

    def init(self, task_description: str, display_resolution: tuple[int, int], save_path: str) -> None:
        self.task_description = task_description
        self.display_resolution = tuple(display_resolution)
        self.save_path = save_path

    # --- subclass hooks -----------------------------------------------------

    def container_env(self) -> dict[str, str]:
        """Runtime configuration to inject into the scratch container."""
        raise NotImplementedError

    def build_cli_command(self) -> str:
        """Shell command that runs the CLI headless inside the container.

        The rendered instruction is available at ``/logs/prompt.txt`` inside
        the container; read it from there to avoid shell-escaping a large
        multi-line prompt.
        """
        raise NotImplementedError

    def prepare_sandbox(self, sandbox: AgentSandbox) -> None:
        """Install private per-run state after the sandbox has started."""

    def collect_sandbox_artifacts(self, sandbox: AgentSandbox) -> None:
        """Export selected per-run state before the sandbox is destroyed."""

    def sandbox_spec(self) -> SandboxSpec:
        return SandboxSpec(
            name=self.sandbox_name,
            base_image=self.sandbox_base_image,
            install=self.sandbox_install,
            act_script=_ACT_SCRIPT,
        )

    # --- episode ------------------------------------------------------------

    def run_episode(self, env: Any, task_description: Optional[str] = None) -> None:
        task = task_description or self.task_description
        resolution = self.display_resolution
        max_steps = int(self.max_steps_override or getattr(env, "max_steps", None) or 50)

        logs_dir = Path(self.save_path) / "cli_harness" if self.save_path else Path(tempfile.mkdtemp())
        logs_dir.mkdir(parents=True, exist_ok=True)
        token = secrets.token_hex(16)
        gateway = ActionGateway(
            env,
            resolution,
            max_steps,
            token,
            temporal_mode=self.temporal_mode,
        )
        sandbox = select_sandbox(self.sandbox_spec(), logs_dir)
        sandbox_started = False

        port = gateway.start(host=sandbox.gateway_bind_host)
        try:
            sandbox.build()
            sandbox.start(gateway_port=port, gateway_token=token, container_env=self.container_env())
            sandbox_started = True
            self.prepare_sandbox(sandbox)
            # The model sees display-sized frames, so the prompt's coordinate
            # space is the display size, not the env's native resolution.
            prompt = build_harness_prompt(
                task,
                (gateway.display_w, gateway.display_h),
                max_steps,
                temporal_mode=self.temporal_mode,
            )
            (logs_dir / "prompt.txt").write_text(prompt)
            result = sandbox.exec(self.build_cli_command(), timeout_sec=self.timeout_sec)
            if result.returncode != 0 and self.verbose:
                logger.warning(
                    "CLI exited with %d; stderr: %s", result.returncode, result.stderr[:2000]
                )
        except subprocess.TimeoutExpired:
            logger.warning("CLI harness timed out after %ds", self.timeout_sec)
        finally:
            self._transcript = gateway.transcript
            gateway.stop()
            if sandbox_started:
                try:
                    self.collect_sandbox_artifacts(sandbox)
                except Exception:
                    logger.warning("Failed to collect CLI sandbox artifacts", exc_info=True)
            sandbox.stop()
            self.done = True

    def finish(self, *args: Any, **kwargs: Any) -> None:
        if not self.save_path:
            return
        trajectory = {
            "agent": type(self).__name__,
            "model": self.model,
            "task": self.task_description,
            "steps": self._transcript,
            "info": kwargs.get("info"),
        }
        try:
            with open(f"{self.save_path}/trajectory.json", "w", encoding="utf-8") as handle:
                json.dump(trajectory, handle, indent=2, default=str)
        except OSError as exc:
            logger.warning("Failed to write CLI harness trajectory: %s", exc)
