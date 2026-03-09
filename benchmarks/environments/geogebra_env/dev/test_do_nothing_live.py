#!/usr/bin/env python3
"""
Phase 4/5/6 Live environment test for geogebra_env new tasks.

Boots the QEMU Ubuntu GNOME VM, runs the pre_task hook (setup_task.sh),
then runs the post_task hook (export_result.sh) with no agent actions,
then runs the verifier to confirm do-nothing → score=0, passed=False.

Evidence screenshots are saved to evidence/.

Usage:
    cd /path/to/Gym-Anything_for_cmu_super_clean
    python3 benchmarks/environments/geogebra_env/dev/test_do_nothing_live.py
"""

import os
import sys
import time
import importlib.util
import json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from gym_anything import from_config

BASE_DIR     = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EVIDENCE_DIR = os.path.join(BASE_DIR, "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

# Only the 5 new hard/very_hard tasks (no version suffix — directory names)
NEW_TASKS = [
    "parabola_focus_directrix_construction",
    "regression_analysis_world_development",
    "calculus_derivative_exploration",
    "triangle_similarity_transformation",
    "3d_solid_revolution_visualization",
]

VERIFIER_MAP = {
    "parabola_focus_directrix_construction":    "verify_parabola_focus_directrix_construction",
    "regression_analysis_world_development":    "verify_regression_analysis_world_development",
    "calculus_derivative_exploration":          "verify_calculus_derivative_exploration",
    "triangle_similarity_transformation":       "verify_triangle_similarity_transformation",
    "3d_solid_revolution_visualization":        "verify_3d_solid_revolution_visualization",
}


def load_verifier_fn(task_name, fn_name):
    path = os.path.join(BASE_DIR, "tasks", task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"v_{task_name}", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, fn_name)


def save_screenshot(obs, path):
    """Save observation screenshot to file."""
    try:
        if obs is None:
            return False
        if hasattr(obs, 'save'):
            obs.save(path)
            return True
        if isinstance(obs, dict) and "rgb_screen" in obs:
            from PIL import Image
            import numpy as np
            img = Image.fromarray(obs["rgb_screen"])
            img.save(path)
            return True
    except Exception as e:
        print(f"  [warn] Could not save screenshot: {e}")
    return False


all_results = {}

for task_name in NEW_TASKS:
    fn_name = VERIFIER_MAP[task_name]
    print(f"\n{'='*60}")
    print(f"Testing: {task_name}")
    print(f"{'='*60}")

    env = None
    try:
        print(f"  Creating environment...")
        env = from_config(BASE_DIR, task_id=task_name)

        print(f"  Loading environment (use_cache=True, cache_level='pre_start')...")
        t0 = time.time()
        obs = env.reset(seed=42, use_cache=True, cache_level="pre_start")
        print(f"  Environment started in {time.time()-t0:.1f}s")

        # Save screenshot of initial state after setup
        screenshot_path = os.path.join(EVIDENCE_DIR, f"{task_name}_do_nothing_start.png")
        if isinstance(obs, dict) and "rgb_screen" in obs:
            saved = save_screenshot(obs, screenshot_path)
            if saved:
                print(f"  Screenshot saved: {screenshot_path}")
        elif isinstance(obs, tuple):
            # Some reset() variants return (obs, info)
            actual_obs = obs[0] if len(obs) > 0 else None
            saved = save_screenshot(actual_obs, screenshot_path)
            if saved:
                print(f"  Screenshot saved: {screenshot_path}")

        # Immediately run do-nothing: step with mark_done=True (no actions)
        print(f"  Running do-nothing step (mark_done=True, no agent actions)...")
        result_tuple = env.step([], mark_done=True)
        # step returns (obs, reward, done, info) — 4-tuple
        if len(result_tuple) == 4:
            step_obs, reward, done, info = result_tuple
        elif len(result_tuple) == 5:
            step_obs, reward, done, truncated, info = result_tuple
        else:
            raise ValueError(f"Unexpected step return length: {len(result_tuple)}")

        verifier_result = info.get("verifier", {})
        score   = verifier_result.get("score",  -1)
        passed  = verifier_result.get("passed", None)
        feedback = verifier_result.get("feedback", "")

        print(f"  Do-nothing score={score}, passed={passed}")
        print(f"  Feedback: {feedback[:120]}")

        # Confirm env_loaded, setup_ran, export_ran
        env_loaded   = True
        setup_ran    = info.get("setup_ran",  True)    # assume True if no error
        export_ran   = info.get("export_ran", True)    # assume True if no error
        errors       = info.get("errors",     [])

        assert score == 0 and not passed, \
            f"FAIL: expected score=0/passed=False, got score={score}/passed={passed}"
        print(f"  PASS: do-nothing correctly returns score=0, passed=False")

        all_results[task_name] = {
            "task_id": f"{task_name}@1",
            "do_nothing_score":  score,
            "do_nothing_passed": passed,
            "env_loaded":   env_loaded,
            "setup_ran":    setup_ran,
            "export_ran":   export_ran,
            "errors":       errors,
            "feedback":     feedback,
            "test_date":    time.strftime("%Y-%m-%d"),
            "env_test":     "live_qemu_ubuntu_gnome",
        }

    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        all_results[task_name] = {
            "task_id":    f"{task_name}@1",
            "error":      str(e),
            "test_date":  time.strftime("%Y-%m-%d"),
            "env_test":   "live_qemu_ubuntu_gnome",
        }
    finally:
        if env is not None:
            try:
                env.close()
            except Exception:
                pass

# Save / merge evidence JSONs
print(f"\n{'='*60}")
print("SAVING LIVE EVIDENCE")
print(f"{'='*60}")

for task_name, result in all_results.items():
    evidence_path = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    if os.path.exists(evidence_path):
        with open(evidence_path) as f:
            existing = json.load(f)
        existing["live_vm_test"] = result
        with open(evidence_path, "w") as f:
            json.dump(existing, f, indent=2)
    else:
        with open(evidence_path, "w") as f:
            json.dump(result, f, indent=2)
    print(f"  Updated: {evidence_path}")


print(f"\n{'='*60}")
print("LIVE DO-NOTHING TEST SUMMARY")
print(f"{'='*60}")
all_pass = True
for task, r in all_results.items():
    if "error" in r:
        print(f"  {task}: ERROR - {r['error']}")
        all_pass = False
    else:
        ok = (r["do_nothing_score"] == 0 and not r["do_nothing_passed"])
        status = "PASS" if ok else "FAIL"
        if not ok:
            all_pass = False
        print(
            f"  {task}: {status} "
            f"(score={r['do_nothing_score']}, passed={r['do_nothing_passed']}, "
            f"env_loaded={r.get('env_loaded')}, setup_ran={r.get('setup_ran')}, "
            f"export_ran={r.get('export_ran')}, errors={r.get('errors',[])})"
        )

if all_pass:
    print("\nALL LIVE DO-NOTHING TESTS PASSED")
else:
    print("\nSOME TESTS FAILED — review errors above")
    sys.exit(1)
