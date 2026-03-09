#!/usr/bin/env python3
"""
Phase 4 testing script for new bahmni_env tasks.
Tests:
1. Environment loads with task
2. Setup script runs (check /tmp files)
3. Export script produces valid JSON
4. Do-nothing test: score=0, passed=False
5. Evidence collection

Run from project root: python3 benchmarks/environments/bahmni_env/dev/test_new_tasks.py
"""

import sys
import os
import time
import json
import subprocess

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')
from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/environments/bahmni_env/evidence'
ENV_NAME = 'bahmni_env'

NEW_TASKS = [
    'chronic_disease_followup',
    'medication_allergy_reconciliation',
    'inpatient_admission_workflow',
    'appointment_schedule_audit',
    'lab_investigation_workflow',
]

os.makedirs(EVIDENCE_DIR, exist_ok=True)


def collect_evidence(env, task_name):
    """Collect evidence: screenshot + basic DB/system checks."""
    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "checks": {}
    }

    # Check setup files exist
    setup_files = env._runner.exec_capture(
        'ls -la /tmp/task_start_timestamp /tmp/task_start.png 2>&1'
    )
    evidence["checks"]["setup_files"] = setup_files.strip()
    print(f"  [SETUP FILES] {setup_files.strip()[:200]}")

    # Check task-specific /tmp files
    tmp_files = env._runner.exec_capture(
        f'ls -la /tmp/{task_name[:3]}* /tmp/cdfu* /tmp/mar_* /tmp/iaw_* /tmp/asa_* /tmp/liw_* 2>&1 | head -20'
    )
    evidence["checks"]["task_tmp_files"] = tmp_files.strip()
    print(f"  [TASK TMP FILES] {tmp_files.strip()[:200]}")

    # Check Docker containers running
    docker_status = env._runner.exec_capture(
        'docker ps --format "{{.Names}}: {{.Status}}" 2>&1 | head -15'
    )
    evidence["checks"]["docker_status"] = docker_status.strip()
    print(f"  [DOCKER] {docker_status.strip()[:300]}")

    # Take screenshot
    env._runner.exec_capture('DISPLAY=:1 scrot /tmp/evidence_screenshot.png 2>&1 || true')
    time.sleep(1)

    screenshot_path = f'{EVIDENCE_DIR}/{task_name}_screenshot.png'
    try:
        env._runner.copy_from('/tmp/task_start.png', screenshot_path)
        evidence["screenshot"] = screenshot_path
        print(f"  [SCREENSHOT] Saved to {screenshot_path}")
    except Exception as e:
        try:
            env._runner.copy_from('/tmp/evidence_screenshot.png', screenshot_path)
            evidence["screenshot"] = screenshot_path
            print(f"  [SCREENSHOT] Saved (fallback) to {screenshot_path}")
        except Exception as e2:
            evidence["screenshot"] = f"ERROR: {str(e2)}"
            print(f"  [SCREENSHOT] FAILED: {e2}")

    return evidence


def test_export_script(env, task_name):
    """Run export script and check output."""
    print(f"\n  [EXPORT] Running export script...")
    export_out = env._runner.exec_capture(
        f'bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1'
    )
    print(f"  [EXPORT OUTPUT] ...{export_out[-500:]}")

    export_complete = "Export Complete" in export_out
    print(f"  [EXPORT] Complete: {export_complete}")

    # Check JSON is valid
    result_file = f'/tmp/{task_name}_result.json'
    json_check = env._runner.exec_capture(
        f'python3 -m json.tool {result_file} > /dev/null 2>&1 && echo "VALID_JSON" || echo "INVALID_JSON"'
    )
    json_valid = "VALID_JSON" in json_check
    print(f"  [EXPORT JSON] Valid: {json_valid}")

    # Get a sample of the JSON
    json_sample = env._runner.exec_capture(
        f'python3 -c "import json; d=json.load(open(\'{result_file}\')); print(json.dumps({{k: v for k,v in list(d.items())[:6]}}, indent=2))" 2>&1'
    )
    print(f"  [EXPORT JSON SAMPLE] {json_sample[:500]}")

    return export_complete, json_valid, json_sample


def do_nothing_test(env, task_name):
    """Run do-nothing test: step with mark_done=True without taking any actions."""
    print(f"\n  [DO-NOTHING TEST] Running...")
    try:
        obs, reward, done, info = env.step([], mark_done=True)
        verifier_result = info.get("verifier", {})
        score = verifier_result.get("score", -1)
        passed = verifier_result.get("passed", None)
        feedback = verifier_result.get("feedback", "")

        print(f"  [DO-NOTHING] Score: {score}")
        print(f"  [DO-NOTHING] Passed: {passed}")
        print(f"  [DO-NOTHING] Feedback: {feedback[:200]}")

        # Validate do-nothing should return score=0
        if score == 0 and passed == False:
            print(f"  [DO-NOTHING] PASS (score=0, passed=False as expected)")
            return True, verifier_result
        else:
            print(f"  [DO-NOTHING] FAIL: expected score=0/passed=False, got score={score}/passed={passed}")
            return False, verifier_result
    except Exception as e:
        print(f"  [DO-NOTHING] ERROR: {e}")
        return False, {"error": str(e)}


def wrong_target_test(env, task_name):
    """
    Inject a wrong patient identifier into the result JSON and verify score=0.
    This tests the wrong-target gate without requiring actual task completion.
    """
    print(f"\n  [WRONG-TARGET TEST] Injecting wrong patient identifier...")
    result_file = f'/tmp/{task_name}_result.json'

    # Get current result
    current_json = env._runner.exec_capture(
        f'cat {result_file} 2>&1'
    )

    try:
        current_data = json.loads(current_json)
    except:
        print(f"  [WRONG-TARGET] Cannot parse result JSON, skipping")
        return None, {}

    # Inject wrong patient identifier
    wrong_data = dict(current_data)
    if 'patient_identifier' in wrong_data:
        original_id = wrong_data['patient_identifier']
        wrong_data['patient_identifier'] = 'BAH999999'
    elif 'patient_identifiers' in wrong_data:
        wrong_data['patient_identifiers'] = ['BAH999999']
    else:
        print(f"  [WRONG-TARGET] No patient_identifier field, checking error handling...")
        wrong_data['patient_identifier'] = 'BAH999999'

    # Write wrong data
    wrong_json_escaped = json.dumps(wrong_data).replace("'", "'\"'\"'")
    env._runner.exec_capture(
        f"python3 -c \"import json; json.dump({json.dumps(wrong_data)}, open('/tmp/{task_name}_result.json', 'w'))\""
    )

    # Run verifier
    obs, reward, done, info = env.step([], mark_done=True)
    verifier_result = info.get("verifier", {})
    score = verifier_result.get("score", -1)
    passed = verifier_result.get("passed", None)
    feedback = verifier_result.get("feedback", "")

    print(f"  [WRONG-TARGET] Score: {score}")
    print(f"  [WRONG-TARGET] Feedback: {feedback[:200]}")

    # Restore original JSON
    env._runner.exec_capture(
        f"python3 -c \"import json; json.dump({json.dumps(current_data)}, open('/tmp/{task_name}_result.json', 'w'))\""
    )

    if score == 0 and passed == False:
        print(f"  [WRONG-TARGET] PASS (score=0 for wrong patient)")
        return True, verifier_result
    else:
        print(f"  [WRONG-TARGET] FAIL: expected score=0, got {score}")
        return False, verifier_result


def test_task(task_name):
    """Full test sequence for a single task."""
    print(f"\n{'='*70}")
    print(f"TESTING TASK: {task_name}")
    print('='*70)

    results = {
        "task": task_name,
        "env_load": False,
        "setup_files": False,
        "export_complete": False,
        "export_json_valid": False,
        "do_nothing_score_zero": False,
        "wrong_target_score_zero": None,
        "errors": []
    }

    env = None
    try:
        print(f"\n[1] Loading environment...")
        env = from_config("benchmarks/environments/bahmni_env", task_id=task_name)
        obs = env.reset(seed=42, use_cache=False)
        print(f"  [ENV] Loaded. VNC: {env._runner.vnc_port if hasattr(env._runner, 'vnc_port') else 'N/A'}")
        results["env_load"] = True

        print(f"\n[2] Collecting evidence...")
        evidence = collect_evidence(env, task_name)

        # Check setup files
        setup_ok = "/tmp/task_start_timestamp" in evidence["checks"].get("setup_files", "")
        results["setup_files"] = setup_ok
        print(f"  [SETUP] Files present: {setup_ok}")

        print(f"\n[3] Testing export script...")
        export_ok, json_ok, json_sample = test_export_script(env, task_name)
        results["export_complete"] = export_ok
        results["export_json_valid"] = json_ok

        print(f"\n[4] Do-nothing test...")
        dn_pass, dn_result = do_nothing_test(env, task_name)
        results["do_nothing_score_zero"] = dn_pass

        print(f"\n[5] Wrong-target test...")
        wt_pass, wt_result = wrong_target_test(env, task_name)
        results["wrong_target_score_zero"] = wt_pass

        # Save evidence JSON
        evidence["test_results"] = results
        evidence["do_nothing_result"] = dn_result
        evidence["wrong_target_result"] = wt_result
        evidence["export_json_sample"] = json_sample

        evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
        with open(evidence_path, 'w') as f:
            json.dump(evidence, f, indent=2)
        print(f"\n  [EVIDENCE] Saved to {evidence_path}")

    except Exception as e:
        print(f"  [ERROR] {e}")
        import traceback
        traceback.print_exc()
        results["errors"].append(str(e))
    finally:
        if env is not None:
            try:
                env.close()
            except:
                pass

    print(f"\n[SUMMARY] {task_name}:")
    for k, v in results.items():
        if k != "errors":
            icon = "✓" if v is True else ("✗" if v is False else f"? ({v})")
            print(f"  {k}: {icon}")
    if results["errors"]:
        print(f"  Errors: {results['errors']}")

    return results


def main():
    all_results = {}

    for task in NEW_TASKS:
        result = test_task(task)
        all_results[task] = result
        time.sleep(2)  # Brief pause between tasks

    print(f"\n{'='*70}")
    print("OVERALL SUMMARY")
    print('='*70)
    for task, res in all_results.items():
        passed = all(v is True for k, v in res.items()
                    if k not in ('errors', 'wrong_target_score_zero', 'task')
                    and v is not None)
        print(f"  {task}: {'PASS' if passed else 'FAIL'}")
        for k, v in res.items():
            if k not in ('errors', 'task'):
                icon = "✓" if v is True else ("✗" if v is False else f"~ ({v})")
                print(f"    {k}: {icon}")

    print(f"\nEvidence saved to: {EVIDENCE_DIR}/")

    # Save overall summary
    summary_path = f'{EVIDENCE_DIR}/test_summary.json'
    with open(summary_path, 'w') as f:
        json.dump({
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "tasks": all_results
        }, f, indent=2)
    print(f"Summary saved to: {summary_path}")


if __name__ == "__main__":
    main()
