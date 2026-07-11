"""Shared machinery for running existing CLI coding harnesses (Claude Code,
Codex CLI, ...) as gym-anything computer-use agents.

Design (see the agents docs): the CLI never runs inside the task VM. It runs
in a throwaway, GUI-less isolated sandbox (apptainer or docker, see
``agent_sandbox.py``) that can reach exactly one thing on the host, an
in-process HTTP *action gateway*, plus the model provider API. The env is a
separate VM, so the CLI has no filesystem path into it and can only affect the
environment through the gateway.

The gateway speaks the same text action vocabulary the other agents use
(``agents/shared/qwen_computer_use.py``): the CLI sends one action as a JSON
string, the gateway parses it, calls ``env.step()``, and returns the
post-action screenshot (base64 PNG) plus the remaining step budget. Inside the
container a tiny ``act`` wrapper POSTs the command and writes the screenshot to
a file the CLI then views. No MCP, no per-CLI protocol.

Because the gateway calls ``env.step()`` for every action, step limits,
timeouts, ``traj.jsonl``, frame capture, and verification all flow through
``GymAnythingEnv`` unchanged — identical to every other agent. The gateway's
own per-action log is the authoritative trajectory record.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import secrets
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from pathlib import Path
from typing import Any, Optional

from PIL import Image

from agents.shared.agent_sandbox import SandboxSpec, select_sandbox
from agents.shared.qwen_computer_use import parse_qwen3vl_response

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


def _obs_png_bytes(obs: dict[str, Any]) -> Optional[bytes]:
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
    if path and os.path.exists(path):
        with open(path, "rb") as handle:
            return handle.read()
    return None


class ActionGateway:
    """Translate CLI action-command strings into ``env.step()`` calls.

    The HTTP surface is a thin wrapper; ``step_from_command`` is the testable
    core (no docker, no sockets). One request is in flight at a time (the CLI
    blocks on each ``act``), so the single env instance is never touched
    concurrently.
    """

    def __init__(
        self,
        env: Any,
        resolution: tuple[int, int],
        max_steps: int,
        token: str,
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
        self.steps_taken = 0
        self.transcript: list[dict[str, Any]] = []
        self._server: Optional[ThreadingHTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    def _display_screenshot_b64(self, obs: dict[str, Any]) -> Optional[str]:
        """Return the observation resized to the display size as a base64 PNG."""
        raw = _obs_png_bytes(obs)
        if raw is None:
            return None
        try:
            img = Image.open(BytesIO(raw))
            if img.size != (self.display_w, self.display_h):
                img = img.resize((self.display_w, self.display_h))
            buffer = BytesIO()
            img.convert("RGB").save(buffer, format="PNG")
            return base64.b64encode(buffer.getvalue()).decode("ascii")
        except Exception:
            # Not a decodable image (e.g. a stub in tests): pass bytes through.
            return base64.b64encode(raw).decode("ascii")

    # --- action translation ------------------------------------------------

    def _env_actions_for(self, command: str) -> tuple[list[dict[str, Any]], bool, Optional[str]]:
        """Return (env_actions, is_terminal, error) for a command string.

        Reuses ``parse_qwen3vl_response`` (single source of truth for the
        action vocabulary) by wrapping the raw action JSON in the tool-call
        envelope the parser expects. The model gives pixel coordinates in the
        display-sized screenshot it was shown; the parser's ``scale_dims``
        ratio maps those display pixels back to the env's native resolution.
        """
        try:
            action_json = json.loads(command)
        except (json.JSONDecodeError, TypeError) as exc:
            return [], False, f"invalid action JSON: {exc}"

        if not isinstance(action_json, dict) or "action" not in action_json:
            return [], False, "action JSON must be an object with an 'action' key"

        name = str(action_json["action"]).lower()
        if name == "screenshot":
            return [{"action": "screenshot"}], False, None
        if name in _TERMINATE_ACTIONS:
            return [], True, None

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
            return [], False, f"could not parse action: {meta.get('conclusion')}"
        env_actions = parsed["actions"]
        if meta.get("wait_time") is not None:
            env_actions = [{"action": "wait", "time": meta["wait_time"]}]
        return env_actions, bool(meta.get("is_terminal")), None

    def step_from_command(self, command: str) -> dict[str, Any]:
        """Execute one action command; return the gateway response payload."""
        if self.steps_taken >= self.max_steps:
            obs = self.env.capture_observation()
            return {
                "step": self.steps_taken,
                "budget_remaining": 0,
                "done": True,
                "error": "step budget exhausted",
                "screenshot_b64": self._display_screenshot_b64(obs),
            }

        env_actions, is_terminal, error = self._env_actions_for(command)

        if error is not None:
            # Do not consume budget on a malformed command; let the model retry.
            obs = self.env.capture_observation()
            self.transcript.append(
                {"step": self.steps_taken, "command": command, "error": error}
            )
            return {
                "step": self.steps_taken,
                "budget_remaining": self.max_steps - self.steps_taken,
                "done": False,
                "error": error,
                "screenshot_b64": self._display_screenshot_b64(obs),
            }

        obs, _reward, done, _info = self.env.step(env_actions)
        self.steps_taken += 1
        self.transcript.append(
            {
                "step": self.steps_taken,
                "command": command,
                "env_actions": env_actions,
                "terminal_requested": is_terminal,
                "env_done": bool(done),
            }
        )
        return {
            "step": self.steps_taken,
            "budget_remaining": max(0, self.max_steps - self.steps_taken),
            "done": bool(done) or is_terminal or self.steps_taken >= self.max_steps,
            "error": None,
            "screenshot_b64": self._display_screenshot_b64(obs),
        }

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


def build_harness_prompt(task_description: str, resolution: tuple[int, int], max_steps: int) -> str:
    """Instruction telling the CLI how to drive the computer through `act`."""
    width, height = resolution
    return f"""You are operating a remote computer to accomplish a task. You CANNOT \
see or touch this computer directly. Your ONLY way to interact with it is the \
`act` command, already installed on your PATH.

`act` takes one JSON action string and returns the path to a screenshot taken \
AFTER the action, plus how many actions you have left. Run it like:

    act '{{"action": "screenshot"}}'
    act '{{"action": "left_click", "coordinate": [960, 540]}}'
    act '{{"action": "type", "text": "hello"}}'

After EVERY `act` call, VIEW the screenshot file it printed (read the image) \
before deciding your next action. Start by taking a screenshot to see the \
current screen.

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
- You have at most {max_steps} actions. Each non-observation `act` call spends one.
- Do NOT try to reach the computer any other way (no ssh, no editing files \
directly, no network tricks). `act` is the only channel and the only thing \
scored. Anything else is impossible and wastes turns.
- When the task is fully complete, call `act '{{"action": "terminate", \
"status": "success"}}'` and stop.

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
if resp.get("screenshot_b64"):
    os.makedirs("obs", exist_ok=True)
    path = f"obs/step_{resp.get('step', 0):04d}.png"
    with open(path, "wb") as fh:
        fh.write(base64.b64decode(resp["screenshot_b64"]))
    print(f"screenshot: {path}  (view this image before your next action)")
if resp.get("error"):
    print(f"error: {resp['error']}")
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
    install line, the container env (API keys), and the CLI invocation.
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
        """API keys / model config to inject into the scratch container."""
        raise NotImplementedError

    def build_cli_command(self) -> str:
        """Shell command that runs the CLI headless inside the container.

        The rendered instruction is available at ``/logs/prompt.txt`` inside
        the container; read it from there to avoid shell-escaping a large
        multi-line prompt.
        """
        raise NotImplementedError

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
        gateway = ActionGateway(env, resolution, max_steps, token)
        sandbox = select_sandbox(self.sandbox_spec(), logs_dir)

        port = gateway.start(host=sandbox.gateway_bind_host)
        try:
            sandbox.build()
            sandbox.start(gateway_port=port, gateway_token=token, container_env=self.container_env())
            # The model sees display-sized frames, so the prompt's coordinate
            # space is the display size, not the env's native resolution.
            prompt = build_harness_prompt(task, (gateway.display_w, gateway.display_h), max_steps)
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
