"""In-container runtime for docker-shaped gym-anything Harbor tasks.

The compiled task's Dockerfile bakes ``environment/gym-anything.json`` into
the image and sets this module as the entrypoint (``serve`` mode). At
container start it boots the task's guest through the standard runner stack
(``qemu_native`` by default: QEMU directly inside the container, the same
shape the ModalRunner sandbox uses) and then serves a small HTTP API on
localhost:

    GET  /health    -> 200 once the environment is booted
    POST /observe   -> {"screenshot_path": ..., "resolution": [w, h]}
    POST /step      -> {"actions": [...]} -> {"done": ..., "action_result": ..., obs}
    POST /finalize  -> run the task's real grading pipeline once;
                       returns {"reward": float, "verifier": {...}}

``tests/test.sh`` calls ``python -m gym_anything.integrations.harbor.container
finalize`` inside the container, which hits ``/finalize`` and writes
``/logs/verifier/reward.json`` in the shape Harbor's Verifier reads. Harbor
agents on the host drive the guest through the same API via
``environment.exec`` + curl (see ``agent.ContainerDriver``).

Grading runs in the container, not in the guest: the same trust boundary the
OSWorld adapter uses (the container wraps the agent-controlled VM).

This module must not import ``harbor``: it runs inside task containers where
only gym-anything is installed. The Harbor-facing backend
(``integrations/harbor/environment.py``) imports the shared boot/grading helpers from
here.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Optional, Tuple
from urllib.request import Request, urlopen

DEFAULT_TASK_CONFIG_PATH = "/harbor-task/gym-anything.json"
DEFAULT_PORT = 7317
DEFAULT_CONTAINER_RUNNER = "qemu"  # auto-selects apptainer/native per host

_REWARD_JSON_PATH = "/logs/verifier/reward.json"
_VERIFIER_JSON_PATH = "/logs/verifier/verifier.json"


# -- shared boot / grading helpers (also used by the Harbor backend) ----------


def boot_env(config: Dict[str, Any], *, force_build: bool = False, default_runner: Optional[str] = None):
    """Boot a GymAnythingEnv from a compiled task's gym-anything.json config.

    The same boot path the verifiers adapter uses, checkpoint caching
    included. Harbor owns the trial's step/time budget, so episode limits are
    effectively disabled.
    """
    from ...config.loading import from_config
    from ...registry import resolve_environment_dir

    env_dir = config.get("env_dir") or resolve_environment_dir(
        config["env_name"], config.get("benchmark")
    )
    runner = config.get("runner") or default_runner
    overrides = {"runner": runner} if runner else None
    env = from_config(env_dir, task_id=config["task_id"], overrides=overrides)
    env.reset(
        seed=int(config.get("seed", 0)),
        use_cache=bool(config.get("use_cache", True)) and not force_build,
        cache_level=config.get("cache_level", "post_start"),
        use_savevm=bool(config.get("use_savevm", False)),
    )
    env.set_episode_limits(max_steps=100_000, timeout_sec=10**9)
    apply_verifier_config(env, config)
    return env


def apply_verifier_config(
    env, config: Dict[str, Any], extra_env: Optional[Dict[str, str]] = None
) -> None:
    """(Re)apply the task's verifier overrides (same shape the prime hub
    loader builds). ``extra_env`` overlays os.environ for the key lookup:
    Harbor delivers the grader key via ``[verifier.env]`` to the verifier
    phase's process, so the key may only become available at finalize time.
    """
    verifier = config.get("verifier") or {}
    if not verifier:
        return
    lookup = {**os.environ, **(extra_env or {})}
    overrides: Dict[str, str] = {}
    if verifier.get("mode"):
        overrides["GYM_ANYTHING_VERIFIER_MODE"] = verifier["mode"]
    if verifier.get("vlm_backend"):
        overrides["VLM_BACKEND"] = verifier["vlm_backend"]
    if verifier.get("vlm_model"):
        overrides["VLM_MODEL"] = verifier["vlm_model"]
    if verifier.get("vlm_base_url"):
        overrides["VLM_BASE_URL"] = verifier["vlm_base_url"]
    key_var = verifier.get("vlm_api_key_var")
    if key_var and lookup.get(key_var):
        overrides["VLM_API_KEY"] = lookup[key_var]
    env.set_verifier_overrides(overrides)


def finalize_episode(env) -> Tuple[float, Optional[Dict[str, Any]]]:
    """Run the task's real grading pipeline (post_task hook + verifier.py)."""
    _obs, reward, _done, step_info = env.step([], mark_done=True)
    verifier = step_info.get("verifier")
    if verifier is None:
        verifier = _read_summary_verifier(env)
    return float(reward or 0.0), verifier


def rewards_from_verdict(
    reward: float, verifier: Optional[Dict[str, Any]]
) -> Dict[str, float]:
    """Map a gym-anything verdict onto Harbor's named-rewards dict."""
    rewards: Dict[str, float] = {"reward": float(reward or 0.0)}
    if isinstance(verifier, dict):
        if "passed" in verifier:
            rewards["passed"] = 1.0 if verifier.get("passed") else 0.0
        score = verifier.get("score")
        if isinstance(score, (int, float)):
            rewards["score"] = float(score)
    return rewards


def _read_summary_verifier(env) -> Optional[Dict[str, Any]]:
    episode_dir = env.episode_dir
    if not episode_dir:
        return None
    try:
        summary = json.loads((Path(episode_dir) / "summary.json").read_text())
    except (OSError, ValueError):
        return None
    return summary.get("verifier")


# -- serve mode ----------------------------------------------------------------


class _Runtime:
    """Owns the booted environment behind a lock; one trial per container."""

    def __init__(self, env, config: Optional[Dict[str, Any]] = None):
        self.env = env
        self.config = config or {}
        self.lock = threading.Lock()
        self._finalize_result: Optional[Dict[str, Any]] = None

    def observe(self) -> Dict[str, Any]:
        with self.lock:
            obs = self.env.capture_observation()
        return _obs_payload(obs)

    def step(self, actions: list) -> Dict[str, Any]:
        with self.lock:
            obs, reward, done, info = self.env.step(actions or [])
        payload = _obs_payload(obs)
        payload.update(
            {
                "reward": float(reward or 0.0),
                "done": bool(done),
                "action_result": info.get("action_result"),
            }
        )
        return payload

    def finalize(self, extra_env: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        with self.lock:
            if self._finalize_result is None:
                # The grader key arrives with the verifier phase (Harbor's
                # [verifier.env]); re-resolve overrides before grading.
                apply_verifier_config(self.env, self.config, extra_env)
                reward, verifier = finalize_episode(self.env)
                self._finalize_result = {"reward": reward, "verifier": verifier}
        return self._finalize_result


def _obs_payload(obs: Dict[str, Any]) -> Dict[str, Any]:
    screen = (obs or {}).get("screen") or {}
    path = screen.get("path")
    return {
        # Absolute: callers (test.sh, the host-side driver) have a different
        # working directory than the serve process.
        "screenshot_path": str(Path(path).resolve()) if path else None,
        "resolution": list(screen.get("resolution") or []),
    }


class _Handler(BaseHTTPRequestHandler):
    runtime: _Runtime  # set by serve()

    def log_message(self, fmt: str, *args: Any) -> None:  # quiet by default
        pass

    def _send_json(self, payload: Dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> Dict[str, Any]:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        return json.loads(self.rfile.read(length))

    def do_GET(self) -> None:  # noqa: N802 (http.server API)
        if self.path == "/health":
            self._send_json({"status": "ready"})
        else:
            self._send_json({"error": f"unknown path {self.path}"}, status=404)

    def do_POST(self) -> None:  # noqa: N802 (http.server API)
        try:
            if self.path == "/observe":
                self._send_json(self.runtime.observe())
            elif self.path == "/step":
                request = self._read_json()
                self._send_json(self.runtime.step(request.get("actions") or []))
            elif self.path == "/finalize":
                request = self._read_json()
                self._send_json(self.runtime.finalize(request.get("env") or None))
            else:
                self._send_json({"error": f"unknown path {self.path}"}, status=404)
        except Exception as exc:  # surface errors to the caller, keep serving
            self._send_json({"error": f"{type(exc).__name__}: {exc}"}, status=500)


_AGENT_MANUAL = """# GUI control API

This container runs a desktop VM with the task's application open. You cannot
see the VM directly; drive it through the local HTTP API:

- `curl -s -X POST http://127.0.0.1:{port}/observe` returns
  `{{"screenshot_path": "...", "resolution": [width, height]}}`. Read the PNG
  at that path to see the current screen.
- `curl -s -X POST -H 'Content-Type: application/json' -d '{{"actions": [...]}}'
  http://127.0.0.1:{port}/step` executes actions and returns the new
  screenshot path. Coordinates are real pixels at the given resolution.

Action objects:

- `{{"mouse": {{"left_click": [x, y]}}}}` (also `double_click`, `right_click`,
  `move`)
- `{{"mouse": {{"scroll": -3}}}}` (negative scrolls down)
- `{{"keyboard": {{"text": "hello"}}}}` types text;
  `{{"keyboard": {{"keys": ["ctrl", "s"]}}}}` presses a chord
- `{{"action": "wait", "time": 2}}` waits

Observe after every step; the screen changes asynchronously. Complete the task
in the GUI; grading runs automatically afterwards against application state.
"""


def _write_agent_manual(port: int) -> None:
    """Give installed CLI agents (Claude Code, Codex, ...) the GUI-control
    affordance: they auto-read AGENTS.md/CLAUDE.md from their working
    directory and are multimodal, so with this manual they can drive the VM
    by reading screenshots and curling actions. Best-effort: root-owned
    paths do not exist outside the task container."""
    content = _AGENT_MANUAL.format(port=port)
    for path in ("/AGENTS.md", "/CLAUDE.md"):
        try:
            Path(path).write_text(content)
        except OSError:
            pass


def _capture_provisioned_screenshot(env) -> None:
    """Persist the just-provisioned screen to /logs/verifier so it survives
    container teardown (Harbor downloads /logs/verifier). This is the boot
    state BEFORE any agent action — used to inspect whether the env's setup
    hooks actually opened the target application. Best-effort.
    """
    import shutil
    import time

    # Give the app time to finish launching after the desktop is ready
    # (slow JVM IDEs, heavy web stacks render seconds after boot). This is a
    # capture-timing concern only; the task itself has the full agent budget.
    settle = int(os.environ.get("GA_HARBOR_SHOT_SETTLE_SEC", "0"))
    if settle > 0:
        time.sleep(settle)

    dest = Path("/logs/verifier/provisioned.png")
    for attempt in range(5):
        try:
            obs = env.capture_observation()
            source = ((obs or {}).get("screen") or {}).get("path")
            if source and Path(source).exists() and Path(source).stat().st_size > 0:
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, dest)
                print(f"[harbor-container] provisioned screenshot -> {dest}")
                return
        except Exception as exc:  # never block serving on the capture
            print(f"[harbor-container] provisioned screenshot attempt {attempt} failed: {exc}")
        time.sleep(3)
    print("[harbor-container] provisioned screenshot: no valid frame after retries")


def serve(config_path: str, port: int) -> None:
    config = json.loads(Path(config_path).read_text())
    print(f"[harbor-container] booting {config.get('env_name')}/{config.get('task_id')}")
    env = boot_env(
        config,
        default_runner=os.environ.get("GA_HARBOR_RUNNER", DEFAULT_CONTAINER_RUNNER),
    )
    _write_agent_manual(port)
    # Harbor expects its log dirs to exist for phase transfers. Best-effort:
    # in the task container this runs as root; a bare process (validation
    # runs outside docker) has no business writing at /.
    for path in ("/logs/agent", "/logs/verifier", "/logs/artifacts"):
        try:
            Path(path).mkdir(parents=True, exist_ok=True)
        except OSError:
            pass

    _capture_provisioned_screenshot(env)

    _Handler.runtime = _Runtime(env, config)
    server = ThreadingHTTPServer(("0.0.0.0", port), _Handler)
    print(f"[harbor-container] ready on :{port}")
    try:
        server.serve_forever()
    finally:
        env.close()


# -- finalize mode (invoked by tests/test.sh inside the container) -------------


def finalize_main(port: int, reward_path: str, verifier_path: str) -> int:
    # Harbor resolves [verifier.env] into THIS process's environment; the
    # serve process booted earlier without it, so forward the credentials.
    payload = json.dumps(
        {"env": {k: v for k, v in os.environ.items() if k.endswith("_API_KEY")}}
    ).encode()
    request = Request(f"http://127.0.0.1:{port}/finalize", data=payload, method="POST")
    with urlopen(request, timeout=1800) as response:
        result = json.loads(response.read())
    if "error" in result:
        print(f"finalize failed: {result['error']}", file=sys.stderr)
        return 1

    verifier = result.get("verifier")
    rewards = rewards_from_verdict(result.get("reward", 0.0), verifier)
    Path(reward_path).parent.mkdir(parents=True, exist_ok=True)
    Path(reward_path).write_text(json.dumps(rewards) + "\n")
    if isinstance(verifier, dict):
        Path(verifier_path).write_text(json.dumps(verifier, default=str, indent=2) + "\n")
        feedback = verifier.get("feedback")
        if feedback:
            print(feedback)
    return 0


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(prog="gym_anything.integrations.harbor.container")
    sub = parser.add_subparsers(dest="mode", required=True)

    serve_parser = sub.add_parser("serve", help="boot the task environment and serve the API")
    serve_parser.add_argument(
        "--config", default=os.environ.get("GA_HARBOR_TASK_CONFIG", DEFAULT_TASK_CONFIG_PATH)
    )
    serve_parser.add_argument(
        "--port", type=int, default=int(os.environ.get("GA_HARBOR_PORT", DEFAULT_PORT))
    )

    finalize_parser = sub.add_parser("finalize", help="grade the episode and write reward.json")
    finalize_parser.add_argument(
        "--port", type=int, default=int(os.environ.get("GA_HARBOR_PORT", DEFAULT_PORT))
    )
    finalize_parser.add_argument("--reward-path", default=_REWARD_JSON_PATH)
    finalize_parser.add_argument("--verifier-path", default=_VERIFIER_JSON_PATH)

    args = parser.parse_args(argv)
    if args.mode == "serve":
        serve(args.config, args.port)
        return 0
    return finalize_main(args.port, args.reward_path, args.verifier_path)


if __name__ == "__main__":
    sys.exit(main())
