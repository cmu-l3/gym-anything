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

``tests/test.sh`` calls ``python -m gym_anything.integrations.harbor_container
finalize`` inside the container, which hits ``/finalize`` and writes
``/logs/verifier/reward.json`` in the shape Harbor's Verifier reads. Harbor
agents on the host drive the guest through the same API via
``environment.exec`` + curl (see ``harbor_agent.ContainerDriver``).

Grading runs in the container, not in the guest: the same trust boundary the
OSWorld adapter uses (the container wraps the agent-controlled VM).

This module must not import ``harbor``: it runs inside task containers where
only gym-anything is installed. The Harbor-facing backend
(``integrations/harbor.py``) imports the shared boot/grading helpers from
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
DEFAULT_CONTAINER_RUNNER = "qemu_native"

_REWARD_JSON_PATH = "/logs/verifier/reward.json"
_VERIFIER_JSON_PATH = "/logs/verifier/verifier.json"


# -- shared boot / grading helpers (also used by the Harbor backend) ----------


def boot_env(config: Dict[str, Any], *, force_build: bool = False, default_runner: Optional[str] = None):
    """Boot a GymAnythingEnv from a compiled task's gym-anything.json config.

    The same boot path the verifiers adapter uses, checkpoint caching
    included. Harbor owns the trial's step/time budget, so episode limits are
    effectively disabled.
    """
    from ..config.loading import from_config
    from ..registry import resolve_environment_dir

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
    return env


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

    def __init__(self, env):
        self.env = env
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

    def finalize(self) -> Dict[str, Any]:
        with self.lock:
            if self._finalize_result is None:
                reward, verifier = finalize_episode(self.env)
                self._finalize_result = {"reward": reward, "verifier": verifier}
        return self._finalize_result


def _obs_payload(obs: Dict[str, Any]) -> Dict[str, Any]:
    screen = (obs or {}).get("screen") or {}
    return {
        "screenshot_path": screen.get("path"),
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
                self._send_json(self.runtime.finalize())
            else:
                self._send_json({"error": f"unknown path {self.path}"}, status=404)
        except Exception as exc:  # surface errors to the caller, keep serving
            self._send_json({"error": f"{type(exc).__name__}: {exc}"}, status=500)


def serve(config_path: str, port: int) -> None:
    config = json.loads(Path(config_path).read_text())
    print(f"[harbor-container] booting {config.get('env_name')}/{config.get('task_id')}")
    env = boot_env(
        config,
        default_runner=os.environ.get("GA_HARBOR_RUNNER", DEFAULT_CONTAINER_RUNNER),
    )
    # Harbor expects its log dirs to exist for phase transfers.
    for path in ("/logs/agent", "/logs/verifier", "/logs/artifacts"):
        Path(path).mkdir(parents=True, exist_ok=True)

    _Handler.runtime = _Runtime(env)
    server = ThreadingHTTPServer(("0.0.0.0", port), _Handler)
    print(f"[harbor-container] ready on :{port}")
    try:
        server.serve_forever()
    finally:
        env.close()


# -- finalize mode (invoked by tests/test.sh inside the container) -------------


def finalize_main(port: int, reward_path: str, verifier_path: str) -> int:
    request = Request(f"http://127.0.0.1:{port}/finalize", data=b"{}", method="POST")
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
    parser = argparse.ArgumentParser(prog="gym_anything.integrations.harbor_container")
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
