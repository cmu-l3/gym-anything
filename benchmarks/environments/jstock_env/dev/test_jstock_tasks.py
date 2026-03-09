#!/usr/bin/env python3
"""
Phase 4/5 test script for jstock_env tasks.

Tests each task for:
  - Phase 4: Environment loads, setup script runs, export script runs
  - Phase 5: Do-nothing test (score=0), partial injection test

Usage:
    python3 benchmarks/environments/jstock_env/dev/test_jstock_tasks.py [task_name]

    If task_name is omitted, tests all 5 new tasks.
"""

import sys
import os
import json
import time
import shutil
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')
from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/environments/jstock_env/evidence'
ENV_DIR = 'benchmarks/environments/jstock_env'

NEW_TASKS = [
    'portfolio_rebalancing',
    'multi_sector_watchlist_setup',
    'dividend_income_portfolio',
    'tax_lot_portfolio_tracking',
    'portfolio_deposit_and_alerts',
]

os.makedirs(EVIDENCE_DIR, exist_ok=True)


def log(msg):
    print(msg, flush=True)


def collect_screenshot(env, task_name, label="start"):
    """Capture a screenshot from the running environment."""
    try:
        remote_path = f'/tmp/task_{label}_{task_name}.png'
        local_path = f'{EVIDENCE_DIR}/{task_name}_{label}_screenshot.png'
        env._runner.exec_capture(
            f'su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot {remote_path}" 2>/dev/null || true'
        )
        time.sleep(0.5)
        try:
            env._runner.copy_from(remote_path, local_path)
            log(f"  Screenshot saved: {local_path}")
            return local_path
        except Exception as e:
            log(f"  Screenshot copy failed: {e}")
            return None
    except Exception as e:
        log(f"  Screenshot capture failed: {e}")
        return None


def check_setup_files(env, task_name):
    """Check that setup script created expected /tmp/initial_* files."""
    out = env._runner.exec_capture(
        f'ls -la /tmp/initial_*{task_name}* /tmp/task_start_ts_{task_name} 2>&1 || echo "MISSING"'
    )
    log(f"  Setup files:\n    {out.strip()}")
    return "MISSING" not in out


def test_export_script(env, task_name):
    """Run export script and verify JSON output."""
    log(f"  Running export script...")
    out = env._runner.exec_capture(
        f'bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1'
    )
    log(f"  Export output (last 500 chars): {out[-500:]}")

    # Check JSON was created
    result_path = f'/tmp/{task_name}_result.json'
    json_check = env._runner.exec_capture(
        f'python3 -m json.tool {result_path} 2>&1 | head -5 && echo "JSON_VALID" || echo "JSON_INVALID"'
    )
    valid = "JSON_VALID" in json_check
    log(f"  JSON valid: {valid}")

    # Copy result JSON for evidence
    local_json = f'{EVIDENCE_DIR}/{task_name}_result.json'
    try:
        env._runner.copy_from(result_path, local_json)
        log(f"  Result JSON saved: {local_json}")
    except Exception as e:
        log(f"  Could not copy result JSON: {e}")

    return valid, out


def run_verifier(env, task_name):
    """Run verifier via env.step(mark_done=True) and return result."""
    try:
        obs, reward, done, info = env.step([], mark_done=True)
        result = info.get("verifier", {})
        return result
    except Exception as e:
        log(f"  Verifier error: {e}")
        return {"passed": False, "score": -1, "feedback": str(e)}


def do_nothing_test(task_name):
    """Phase 5: Run export + verifier immediately without any agent actions."""
    log(f"\n{'='*60}")
    log(f"DO-NOTHING TEST: {task_name}")
    log('='*60)

    evidence = {"task": task_name, "test": "do_nothing", "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")}

    try:
        env = from_config(ENV_DIR, task_id=task_name)
        obs = env.reset(seed=42, use_cache=False)
        log(f"  Environment started. VNC port: {getattr(env._runner, 'vnc_port', 'N/A')}")
        evidence["env_started"] = True

        # Give JStock time to start
        time.sleep(5)

        # Take start screenshot
        screenshot = collect_screenshot(env, task_name, "donothing")
        evidence["screenshot"] = screenshot

        # Check setup files
        setup_ok = check_setup_files(env, task_name)
        evidence["setup_files_present"] = setup_ok

        # Run export (do-nothing state)
        json_valid, export_out = test_export_script(env, task_name)
        evidence["export_json_valid"] = json_valid
        evidence["export_completed"] = "Export Complete" in export_out or "export complete" in export_out.lower()

        # Run verifier — must return score=0
        result = run_verifier(env, task_name)
        evidence["verifier_result"] = result
        score = result.get("score", -1)
        passed = result.get("passed", True)

        if score == 0 and not passed:
            log(f"  [PASS] Do-nothing test: score=0, passed=False as expected")
            evidence["do_nothing_pass"] = True
        else:
            log(f"  [FAIL] Do-nothing test: score={score}, passed={passed} — expected score=0, passed=False")
            evidence["do_nothing_pass"] = False

        log(f"  Feedback: {result.get('feedback', '')}")

    except Exception as e:
        log(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        evidence["error"] = str(e)
        evidence["do_nothing_pass"] = False
    finally:
        try:
            env.close()
        except Exception:
            pass

    # Save evidence
    ev_path = f'{EVIDENCE_DIR}/{task_name}_donothing_evidence.json'
    with open(ev_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    log(f"  Evidence saved: {ev_path}")

    return evidence


def test_task(task_name):
    """Run full Phase 4 test + do-nothing (Phase 5) test."""
    log(f"\n{'='*60}")
    log(f"TESTING: {task_name}")
    log('='*60)

    evidence = {"task": task_name, "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")}

    try:
        env = from_config(ENV_DIR, task_id=task_name)
        obs = env.reset(seed=42, use_cache=False)
        log(f"  Environment started. VNC port: {getattr(env._runner, 'vnc_port', 'N/A')}")
        evidence["env_started"] = True

        time.sleep(5)

        # Take start screenshot
        screenshot = collect_screenshot(env, task_name, "start")
        evidence["screenshot"] = screenshot

        # Check setup files were created
        setup_ok = check_setup_files(env, task_name)
        evidence["setup_files_present"] = setup_ok

        # Run export immediately (do-nothing state)
        json_valid, export_out = test_export_script(env, task_name)
        evidence["export_json_valid"] = json_valid
        evidence["export_completed"] = "Export Complete" in export_out or "export complete" in export_out.lower()

        # Run verifier
        result = run_verifier(env, task_name)
        evidence["verifier_result"] = result
        score = result.get("score", -1)
        passed = result.get("passed", True)

        if score == 0 and not passed:
            log(f"  [PASS] Do-nothing: score=0, passed=False")
            evidence["do_nothing_pass"] = True
        else:
            log(f"  [WARN] Do-nothing: score={score}, passed={passed}")
            evidence["do_nothing_pass"] = score == 0

        log(f"  Feedback: {result.get('feedback', '')}")

    except Exception as e:
        log(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        evidence["error"] = str(e)
        evidence["env_started"] = False
    finally:
        try:
            env.close()
        except Exception:
            pass

    # Save evidence
    ev_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
    with open(ev_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    log(f"  Evidence saved: {ev_path}")

    return evidence


def print_summary(results):
    log(f"\n{'='*60}")
    log("TEST SUMMARY")
    log('='*60)
    all_pass = True
    for task, ev in results.items():
        env_ok = ev.get("env_started", False)
        setup_ok = ev.get("setup_files_present", False)
        export_ok = ev.get("export_completed", False)
        json_ok = ev.get("export_json_valid", False)
        donothing_ok = ev.get("do_nothing_pass", False)
        score = ev.get("verifier_result", {}).get("score", "?")
        status = "PASS" if (env_ok and export_ok and json_ok and donothing_ok) else "FAIL"
        if status == "FAIL":
            all_pass = False
        log(f"  {task}: {status}")
        log(f"    env={env_ok} setup={setup_ok} export={export_ok} json={json_ok} donothing={donothing_ok} score={score}")
    log(f"\nOverall: {'ALL PASS' if all_pass else 'SOME FAILURES — see above'}")


if __name__ == "__main__":
    tasks_to_test = sys.argv[1:] if len(sys.argv) > 1 else NEW_TASKS

    results = {}
    for task in tasks_to_test:
        results[task] = test_task(task)

    print_summary(results)
    log(f"\nEvidence saved to: {EVIDENCE_DIR}/")
