#!/usr/bin/env python3
"""
Phase 4/5/6 Live environment test for electrical_calculations_env new tasks.

Boots the Android AVD, runs the pre_task hook (setup_task.sh),
takes a screenshot, runs the post_task hook (export_result.sh),
then runs the verifier to confirm do-nothing → score=0, passed=False.

Evidence screenshots are saved to evidence/.
"""

import os
import sys
import time
import importlib.util
import json
import shutil

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from gym_anything import from_config

BASE_DIR     = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EVIDENCE_DIR = os.path.join(BASE_DIR, "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

NEW_TASKS = [
    "three_phase_load_analysis@1",
    "single_phase_power_quality_audit@1",
    "motor_cable_sizing_calculation@1",
    "delta_wye_resistor_network@1",
    "three_phase_line_phase_conversions@1",
]

def load_verifier_fn(task_name, fn_name):
    path = os.path.join(BASE_DIR, "tasks", task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"v_{task_name}", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, fn_name)

VERIFIER_MAP = {
    "three_phase_load_analysis":        "verify_three_phase_load_analysis",
    "single_phase_power_quality_audit": "verify_single_phase_power_quality_audit",
    "motor_cable_sizing_calculation":   "verify_motor_cable_sizing_calculation",
    "delta_wye_resistor_network":       "verify_delta_wye_resistor_network",
    "three_phase_line_phase_conversions": "verify_three_phase_line_phase_conversions",
}

all_results = {}

for task_id in NEW_TASKS:
    task_name = task_id.split("@")[0]
    fn_name   = VERIFIER_MAP[task_name]
    print(f"\n{'='*60}")
    print(f"Testing: {task_id}")
    print(f"{'='*60}")

    env = None
    try:
        env = from_config(BASE_DIR, task_id=task_id)
        print("  Loading environment (use_cache=True, use_savevm=True)...")
        obs, info = env.reset(seed=42, use_cache=True, use_savevm=True)
        print("  Environment started successfully.")

        # Save main screenshot evidence
        if obs is not None and hasattr(obs, 'save'):
            screenshot_path = os.path.join(EVIDENCE_DIR, f"{task_name}_do_nothing_start.png")
            obs.save(screenshot_path)
            print(f"  Screenshot saved: {screenshot_path}")
        elif isinstance(obs, dict) and "rgb_screen" in obs:
            import numpy as np
            from PIL import Image
            img = Image.fromarray(obs["rgb_screen"])
            screenshot_path = os.path.join(EVIDENCE_DIR, f"{task_name}_do_nothing_start.png")
            img.save(screenshot_path)
            print(f"  Screenshot saved: {screenshot_path}")

        # Run verifier (do-nothing — no agent actions taken)
        task_json_path = os.path.join(BASE_DIR, "tasks", task_name, "task.json")
        with open(task_json_path) as f:
            task_info = json.load(f)

        verifier_fn = load_verifier_fn(task_name, fn_name)
        result = verifier_fn(
            traj=[],
            env_info=env.env_info if hasattr(env, 'env_info') else info,
            task_info=task_info
        )

        print(f"  Do-nothing result: score={result['score']}, passed={result['passed']}")
        print(f"  Feedback: {result['feedback']}")

        assert result['score'] == 0 and not result['passed'], \
            f"FAIL: expected score=0/passed=False, got score={result['score']}/passed={result['passed']}"

        print(f"  PASS: do-nothing correctly returns score=0, passed=False")

        all_results[task_name] = {
            "task_id": task_id,
            "do_nothing_score": result["score"],
            "do_nothing_passed": result["passed"],
            "feedback": result["feedback"],
            "test_date": time.strftime("%Y-%m-%d"),
            "env_test": "live_android_avd",
        }

    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        all_results[task_name] = {
            "task_id": task_id,
            "error": str(e),
            "test_date": time.strftime("%Y-%m-%d"),
        }
    finally:
        if env is not None:
            try:
                env.close()
            except Exception:
                pass

# Save live test evidence
for task_name, result in all_results.items():
    # Merge with pipeline evidence if it exists
    evidence_path = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    if os.path.exists(evidence_path):
        with open(evidence_path) as f:
            existing = json.load(f)
        existing["live_vm_test"] = result
        with open(evidence_path, "w") as f:
            json.dump(existing, f, indent=2)
        print(f"Updated evidence: {evidence_path}")
    else:
        with open(evidence_path, "w") as f:
            json.dump(result, f, indent=2)
        print(f"Saved evidence: {evidence_path}")

print(f"\n{'='*60}")
print("LIVE DO-NOTHING TEST SUMMARY")
print(f"{'='*60}")
for task, r in all_results.items():
    if "error" in r:
        print(f"  {task}: ERROR - {r['error']}")
    else:
        status = "PASS" if r["do_nothing_score"] == 0 and not r["do_nothing_passed"] else "FAIL"
        print(f"  {task}: {status} (score={r['do_nothing_score']}, passed={r['do_nothing_passed']})")
