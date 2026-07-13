#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import signal
import threading
import traceback
from pathlib import Path


EVENT_PREFIX = "__CAPTCHA_HUB_EVENT__"


def emit(event: str, **payload: object) -> None:
    print(f"{EVENT_PREFIX}{json.dumps({'event': event, **payload}, sort_keys=True)}", flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Boot one Gym-Anything environment for the CAPTCHA Bench dashboard.")
    parser.add_argument("--env-dir", required=True)
    parser.add_argument("--task", required=True)
    parser.add_argument("--runner", default="avf")
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    stop = threading.Event()

    def request_stop(_signum: int, _frame: object) -> None:
        stop.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    os.environ["GYM_ANYTHING_RUNNER"] = args.runner

    from gym_anything import from_config

    env = None
    try:
        emit("phase", phase="booting", message="Preparing the virtual environment")
        env = from_config(str(Path(args.env_dir).resolve()), task_id=args.task)
        emit("phase", phase="booting", message="Launching runner and installing task state")
        env.reset(seed=args.seed)
        session = env.get_session_info()
        if session is None:
            raise RuntimeError("runner did not publish SessionInfo")
        emit("ready", session=session.to_dict())
        while not stop.wait(0.4):
            pass
        emit("phase", phase="stopping", message="Stopping environment")
        return 0
    except BaseException as exc:
        emit("error", message=str(exc), detail=traceback.format_exc(limit=8))
        return 1
    finally:
        if env is not None:
            try:
                env.close()
            except Exception as exc:
                emit("log", message=f"cleanup warning: {exc}")
        emit("stopped")


if __name__ == "__main__":
    raise SystemExit(main())
