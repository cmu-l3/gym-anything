#!/usr/bin/env python3
"""
Phase 4 Live do-nothing test for jfrog_artifactory_env new tasks.

Boots the QEMU Ubuntu GNOME VM, runs the pre_task hook (setup_task.sh),
then runs the post_task hook (export_result.sh) with no agent actions,
then runs the verifier to confirm do-nothing -> score=0, passed=False.

Usage:
    cd /path/to/Gym-Anything_for_cmu_super_clean
    python3 benchmarks/environments/jfrog_artifactory_env/dev/test_do_nothing_live.py
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

NEW_TASKS = [
    "tradex_platform_setup",
    "security_hardening_service_account",
    "federated_npm_registry_setup",
    "multi_team_pypi_infrastructure",
    "setup_release_pipeline_repos",
]

VERIFIER_MAP = {
    "tradex_platform_setup":               "verify_tradex_platform_setup",
    "security_hardening_service_account":  "verify_security_hardening_service_account",
    "federated_npm_registry_setup":        "verify_federated_npm_registry_setup",
    "multi_team_pypi_infrastructure":      "verify_multi_team_pypi_infrastructure",
    "setup_release_pipeline_repos":        "verify_setup_release_pipeline_repos",
}


def save_screenshot(obs, path):
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

        # Save initial screenshot
        screenshot_path = os.path.join(EVIDENCE_DIR, f"{task_name}_do_nothing_start.png")
        actual_obs = obs[0] if isinstance(obs, tuple) else obs
        save_screenshot(actual_obs, screenshot_path)

        # Do-nothing step
        print(f"  Running do-nothing step (mark_done=True, no agent actions)...")
        result_tuple = env.step([], mark_done=True)
        if len(result_tuple) == 4:
            step_obs, reward, done, info = result_tuple
        elif len(result_tuple) == 5:
            step_obs, reward, done, truncated, info = result_tuple
        else:
            raise ValueError(f"Unexpected step return length: {len(result_tuple)}")

        # Extract verifier result — may be nested under "verifier" or at top level
        if "verifier" in info:
            verifier_result = info["verifier"]
        else:
            verifier_result = info

        score    = verifier_result.get("score",    -1)
        passed   = verifier_result.get("passed",   None)
        feedback = verifier_result.get("feedback", "")

        print(f"  Do-nothing score={score}, passed={passed}")
        print(f"  Feedback: {feedback[:200]}")

        ok = (score == 0 and passed is False)
        assert ok, f"FAIL: expected score=0/passed=False, got score={score}/passed={passed}"
        print(f"  PASS: do-nothing correctly returns score=0, passed=False")

        all_results[task_name] = {
            "task_id":           f"{task_name}@1",
            "do_nothing_score":  score,
            "do_nothing_passed": passed,
            "feedback":          feedback,
            "test_date":         time.strftime("%Y-%m-%d"),
            "env_test":          "live_qemu_ubuntu_gnome",
        }

    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        all_results[task_name] = {
            "task_id":   f"{task_name}@1",
            "error":     str(e),
            "test_date": time.strftime("%Y-%m-%d"),
            "env_test":  "live_qemu_ubuntu_gnome",
        }
    finally:
        if env is not None:
            try:
                env.close()
            except Exception:
                pass

# Update evidence JSON
print(f"\n{'='*60}")
print("UPDATING EVIDENCE JSON")
print(f"{'='*60}")

evidence_path = os.path.join(EVIDENCE_DIR, "new_tasks_evidence.json")
if os.path.exists(evidence_path):
    with open(evidence_path) as f:
        evidence = json.load(f)
else:
    evidence = {}

evidence["live_do_nothing_tests"] = {
    "run_date": time.strftime("%Y-%m-%d %H:%M:%S"),
    "results":  all_results,
}

with open(evidence_path, "w") as f:
    json.dump(evidence, f, indent=2)
print(f"  Updated: {evidence_path}")

# Summary
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
        print(f"  {task}: {status} (score={r['do_nothing_score']}, passed={r['do_nothing_passed']})")
        if r.get("feedback"):
            print(f"           feedback: {r['feedback'][:120]}")

if all_pass:
    print("\nALL LIVE DO-NOTHING TESTS PASSED")
else:
    print("\nSOME TESTS FAILED — review errors above")
    sys.exit(1)
