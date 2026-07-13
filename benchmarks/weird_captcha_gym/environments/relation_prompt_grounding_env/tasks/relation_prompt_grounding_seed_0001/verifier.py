from __future__ import annotations

import importlib.util
from pathlib import Path


BENCHMARK_ROOT = Path(__file__).resolve().parents[4]
HELPER_PATH = BENCHMARK_ROOT / "shared_runtime" / "verifier_helpers.py"
GRADER_PATH = BENCHMARK_ROOT / "shared_runtime" / "server" / "incubator_graders" / "relation_prompt_grounding.py"


def _load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_task(traj=None, env_info=None, task_info=None):
    del traj, task_info
    try:
        helpers = _load_module("weird_captcha_verifier_helpers", HELPER_PATH)
        grader = _load_module("relation_prompt_grounding_grader", GRADER_PATH)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": str(exc)}
    exported, error = helpers.load_exported_result(env_info or {})
    if error:
        return {"passed": False, "score": 0, "feedback": error}
    exported = exported or {}
    result = exported.get("result") or {}
    if not result:
        return {"passed": False, "score": 0, "feedback": "No submitted UI result found."}
    grade = grader.grade(result, exported.get("ground_truth") or {}, exported.get("public_state") or {})
    passed = grade.get("passed") is True
    return {"passed": passed, "score": 100 if passed else 0, "feedback": str(grade.get("feedback") or "relation-assembly grade unavailable")}
