#!/usr/bin/env python3
"""Launch a live Weird CAPTCHA Gym session and keep it open for VNC use."""

from __future__ import annotations

import argparse
import json
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from gym_anything.api import from_config


_running = True


def _handle_stop(_signum: int, _frame: Any) -> None:
    global _running
    _running = False


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _open_vnc(port: int) -> None:
    if sys.platform == "darwin":
        subprocess.Popen(["open", f"vnc://localhost:{port}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif sys.platform.startswith("linux"):
        subprocess.Popen(["xdg-open", f"vnc://localhost:{port}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("env_dir")
    parser.add_argument("--task", required=True)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--ready-json", default="/tmp/weird-captcha-live-avf-session.json")
    parser.add_argument("--open-vnc", action="store_true")
    args = parser.parse_args()

    signal.signal(signal.SIGINT, _handle_stop)
    signal.signal(signal.SIGTERM, _handle_stop)

    env = from_config(args.env_dir, task_id=args.task)
    try:
        env.reset(seed=args.seed)
        session = env.get_session_info()
        payload = session.to_dict() if session else {}
        payload["episode_dir"] = str(env.episode_dir) if env.episode_dir else None
        _write_json(Path(args.ready_json), payload)

        vnc_port = payload.get("vnc_port")
        if args.open_vnc and isinstance(vnc_port, int):
            _open_vnc(vnc_port)

        print(json.dumps(payload, indent=2), flush=True)
        while _running:
            time.sleep(1)
    finally:
        env.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
