from __future__ import annotations

import importlib.util
import json
import os
import tempfile
from pathlib import Path
from typing import Any


BENCHMARK_ROOT = Path(__file__).resolve().parents[4]
GRADER_PATH = BENCHMARK_ROOT / "shared_runtime" / "server" / "incubator_graders" / "photograph_eats_the_room.py"


def _load_export(env_info: dict[str, Any]) -> tuple[dict[str, Any] | None, str | None]:
    copier = env_info.get("copy_from_env")
    if not callable(copier): return None, "copy_from_env unavailable"
    handle = tempfile.NamedTemporaryFile(delete=False, suffix=".json"); handle.close()
    try:
        copier("/tmp/task_result.json", handle.name)
        with open(handle.name, "r", encoding="utf-8") as stream: exported = json.load(stream)
    except Exception as exc: return None, f"error reading /tmp/task_result.json: {exc}"
    finally:
        try: os.unlink(handle.name)
        except FileNotFoundError: pass
    return (exported, None) if isinstance(exported, dict) else (None, "exported result is not an object")


def verify_task(traj=None, env_info=None, task_info=None):
    del traj, task_info
    exported, error = _load_export(env_info or {})
    if error: return {"passed": False, "score": 0, "feedback": error}
    result = (exported or {}).get("result")
    if not isinstance(result, dict) or not result: return {"passed": False, "score": 0, "feedback": "No submitted UI result found."}
    spec = importlib.util.spec_from_file_location("photograph_room_independent_grader", GRADER_PATH)
    if spec is None or spec.loader is None: return {"passed": False, "score": 0, "feedback": "cannot load independent grader"}
    grader = importlib.util.module_from_spec(spec); spec.loader.exec_module(grader)
    decision = grader.grade(result, (exported or {}).get("ground_truth") or {}, (exported or {}).get("public_state") or {})
    passed = bool(decision.get("passed"))
    return {"passed": passed, "score": 100 if passed else 0, "feedback": f"independent perspective/collision replay: {decision.get('feedback') or 'verification failed'}"}
