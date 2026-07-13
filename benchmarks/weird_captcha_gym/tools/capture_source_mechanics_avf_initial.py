#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path
from typing import Any

from gym_anything.api import from_config


ROOT = Path(__file__).resolve().parents[3]
BENCH_ROOT = ROOT / "benchmarks" / "weird_captcha_gym"

MECHANICS = (
    "semantic_drag_drop_absurdity",
    "reload_interruption",
    "rotate_wrong_thing_upright",
    "bureaucratic_signature_trap",
    "wonky_text_hostile_rendering",
    "temporal_memory_first_change",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Capture AVF reset screenshots for source-grounded mechanics.")
    parser.add_argument("--out-dir", default=str(BENCH_ROOT / "evidence" / "source_mechanics_v1_avf"))
    parser.add_argument("--seed-base", type=int, default=4100)
    parser.add_argument("--wait-seconds", type=float, default=3.0)
    parser.add_argument("--mechanic", action="append", choices=MECHANICS)
    return parser.parse_args()


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _portable_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(ROOT).as_posix()
    except ValueError:
        return str(resolved)


def capture_one(mechanic: str, out_dir: Path, seed: int, wait_seconds: float) -> dict[str, Any]:
    env_dir = BENCH_ROOT / "environments" / f"{mechanic}_env"
    task_id = f"{mechanic}_seed_0001"
    env = from_config(str(env_dir), task_id=task_id)
    try:
        observation = env.reset(seed=seed)
        if wait_seconds > 0:
            observation, _, _, _ = env.step([{"action": "wait", "seconds": wait_seconds}], wait_between_actions=0)
        screen_path = Path(observation["screen"]["path"])
        target = out_dir / f"{mechanic}-initial.png"
        shutil.copy2(screen_path, target)
        session = env.get_session_info()
        session_payload = session.to_dict() if session else {}
        _write_json(out_dir / f"{mechanic}-session.json", session_payload)
        return {
            "ok": True,
            "mechanic": mechanic,
            "runner": env.runner_name,
            "screenshot": _portable_path(target),
            "session": session_payload,
        }
    finally:
        env.close()


def main() -> None:
    args = parse_args()
    os.environ.setdefault("GYM_ANYTHING_POST_TASK_SETTLE_SEC", "0")
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    mechanics = tuple(args.mechanic) if args.mechanic else MECHANICS
    results: dict[str, Any] = {}
    for index, mechanic in enumerate(mechanics):
        results[mechanic] = capture_one(mechanic, out_dir, args.seed_base + index, args.wait_seconds)

    summary = {"ok": True, "mechanics": results, "out_dir": _portable_path(out_dir)}
    _write_json(out_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
