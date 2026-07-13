from __future__ import annotations

import importlib.util
from pathlib import Path


BENCHMARK_ROOT = Path(__file__).resolve().parents[4]
HELPER_PATH = BENCHMARK_ROOT / "shared_runtime" / "verifier_helpers.py"


def _load_helpers():
    spec = importlib.util.spec_from_file_location("weird_captcha_verifier_helpers", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load verifier helper from {HELPER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_task(traj, env_info, task_info):
    helpers = _load_helpers()
    exported, error = helpers.load_exported_result(env_info)
    if error:
        return {
            "passed": False,
            "score": 0,
            "feedback": error,
        }
    return helpers.verify_reverse_identity_gate(exported)
