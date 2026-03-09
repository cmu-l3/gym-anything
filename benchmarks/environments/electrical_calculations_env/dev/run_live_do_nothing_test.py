#!/usr/bin/env python3
"""
Phase 4/5/6: Live do-nothing test for the 5 new electrical_calculations_env tasks.

For each task:
  1. Boot Android AVD with pre_start checkpoint (use_cache=True, use_savevm=True)
  2. Take a screenshot showing app state after setup
  3. Immediately call step([], mark_done=True) — no agent actions
     This runs the post_task hook (export_result.sh → uiautomator dump)
     and then the verifier
  4. Assert result: score=0, passed=False
  5. Save screenshot + evidence JSON to evidence/

Usage:
  python3 run_live_do_nothing_test.py
"""

import os
import sys
import json
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

from gym_anything import from_config

BASE_DIR     = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EVIDENCE_DIR = os.path.join(BASE_DIR, "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

NEW_TASKS = [
    "three_phase_load_analysis",
    "single_phase_power_quality_audit",
    "motor_cable_sizing_calculation",
    "delta_wye_resistor_network",
    "three_phase_line_phase_conversions",
]

all_results = {}
all_pass = True

for task_name in NEW_TASKS:
    print(f"\n{'='*60}")
    print(f"Task: {task_name}")
    print(f"{'='*60}")

    env = None
    try:
        # Load environment config for this task
        env = from_config(BASE_DIR, task_id=task_name)
        print(f"  Resetting environment (use_cache=True)...")
        t0 = time.time()
        obs = env.reset(seed=42, use_cache=True)
        print(f"  Reset complete in {time.time()-t0:.1f}s")

        # Save a screenshot of the initial state (app after setup_task.sh)
        try:
            screenshot_path = os.path.join(EVIDENCE_DIR, f"{task_name}_initial_state.png")
            env._runner.capture_screenshot(screenshot_path)
            print(f"  Initial screenshot: {screenshot_path}")
        except Exception as e:
            print(f"  Screenshot failed: {e}")

        # Do-nothing: call step with empty actions and mark_done=True
        # This triggers: export_result.sh (uiautomator dump) + verifier
        print(f"  Running do-nothing step (mark_done=True)...")
        t1 = time.time()
        obs2, reward, done, info = env.step([], mark_done=True)
        print(f"  Step complete in {time.time()-t1:.1f}s")

        verifier_result = info.get("verifier", {})
        score   = verifier_result.get("score", -1)
        passed  = verifier_result.get("passed", None)
        feedback = verifier_result.get("feedback", "")

        print(f"  score={score}, passed={passed}")
        print(f"  feedback: {feedback}")

        # Validate do-nothing result
        if score == 0 and passed == False:
            print(f"  PASS: do-nothing correctly returns score=0, passed=False")
            task_pass = True
        else:
            print(f"  FAIL: expected score=0/passed=False, got score={score}/passed={passed}")
            task_pass = False
            all_pass = False

        all_results[task_name] = {
            "task_id": f"{task_name}@1",
            "do_nothing_score":  score,
            "do_nothing_passed": passed,
            "feedback": feedback,
            "reward": reward,
            "test_pass": task_pass,
            "test_date": time.strftime("%Y-%m-%d"),
            "env_test": "live_android_avd_34",
        }

    except Exception as e:
        import traceback
        print(f"  ERROR: {e}")
        traceback.print_exc()
        all_pass = False
        all_results[task_name] = {
            "task_id": f"{task_name}@1",
            "error": str(e),
            "test_date": time.strftime("%Y-%m-%d"),
        }
    finally:
        if env is not None:
            try:
                env.close()
            except Exception:
                pass

# Merge results into existing evidence JSON files
print(f"\n{'='*60}")
print("SAVING EVIDENCE")
print(f"{'='*60}")

for task_name, live_result in all_results.items():
    evidence_path = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    if os.path.exists(evidence_path):
        with open(evidence_path) as f:
            evidence = json.load(f)
    else:
        evidence = {"task": task_name}

    evidence["live_vm_test"] = live_result
    with open(evidence_path, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"  Updated: {evidence_path}")

print(f"\n{'='*60}")
print("LIVE DO-NOTHING TEST SUMMARY")
print(f"{'='*60}")
for task, r in all_results.items():
    if "error" in r:
        print(f"  {task}: ERROR - {r['error']}")
    else:
        status = "PASS" if r.get("test_pass") else "FAIL"
        print(f"  {task}: {status} (score={r['do_nothing_score']}, passed={r['do_nothing_passed']})")

sys.exit(0 if all_pass else 1)
