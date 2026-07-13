from __future__ import annotations

import importlib.util
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parents[4]
HELPER_PATH = BENCHMARK_ROOT / "shared_runtime" / "verifier_helpers.py"

def verify_task(traj=None, env_info=None, task_info=None):
    spec = importlib.util.spec_from_file_location("weird_captcha_verifier_helpers", HELPER_PATH)
    if spec is None or spec.loader is None:
        return {"passed": False, "score": 0, "feedback": f"cannot load verifier helper from {HELPER_PATH}"}
    helpers = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helpers)
    exported, error = helpers.load_exported_result(env_info or {})
    if error:
        return {"passed": False, "score": 0, "feedback": error}
    return helpers.verify_parallel_grillmaster(exported or {})
