from __future__ import annotations

import importlib.util
from pathlib import Path


BENCHMARK_ROOT = Path(__file__).resolve().parents[4]
HELPER_PATH = BENCHMARK_ROOT / "shared_runtime" / "verifier_helpers.py"
GRADER_PATH = BENCHMARK_ROOT / "shared_runtime" / "server" / "incubator_graders" / "minecraft_block_grid.py"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_task(traj=None, env_info=None, task_info=None):
    del traj, task_info
    try:
        helpers = _load_module("weird_captcha_verifier_helpers", HELPER_PATH)
        grader = _load_module("minecraft_voxel_independent_grader", GRADER_PATH)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"cannot load verifier dependency: {exc}"}
    exported, error = helpers.load_exported_result(env_info or {})
    if error:
        return {"passed": False, "score": 0, "feedback": error}
    exported = exported or {}
    replay = grader.grade(exported.get("result") or {}, exported.get("ground_truth") or {}, exported.get("public_state") or {})
    passed = replay.get("passed") is True
    return {"passed": passed, "score": 100 if passed else 0, "feedback": f"independent voxel-ray replay: {replay.get('feedback') or 'no feedback'}"}
