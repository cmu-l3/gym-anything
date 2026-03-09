#!/usr/bin/env python3
"""
Evidence collection and testing script for new nosh_env tasks.

Tests all 5 new tasks:
  - hypertension_panel_remediation
  - vaccine_audit_and_schedule
  - post_visit_documentation_workflow
  - allergy_drug_conflict_resolution
  - diabetic_care_gap_intervention

For each task, this script:
  1. Boots the environment with the task
  2. Runs the do-nothing test (export immediately, verify score=0)
  3. Captures a screenshot of the starting state
  4. Queries the DB to verify seeded data
  5. Saves evidence JSON to evidence/

Usage:
  cd /path/to/Gym-Anything_for_cmu_super_clean
  python3 benchmarks/environments/nosh_env/dev/test_new_tasks.py [task_name]

  If task_name is provided, only that task is tested.
  Without arguments, all 5 new tasks are tested sequentially.
"""

import sys
import os
import time
import json
import tempfile
import importlib.util

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')

EVIDENCE_DIR = 'benchmarks/environments/nosh_env/evidence'
ENV_NAME = 'benchmarks/environments/nosh_env'

NEW_TASKS = [
    'hypertension_panel_remediation',
    'vaccine_audit_and_schedule',
    'post_visit_documentation_workflow',
    'allergy_drug_conflict_resolution',
    'diabetic_care_gap_intervention',
]

# Task-specific DB queries for evidence collection
TASK_QUERIES = {
    'hypertension_panel_remediation': {
        'patients': "SELECT pid, lastname, firstname, sex, DOB FROM demographics WHERE pid IN (22,23,24,25,26) ORDER BY pid",
        'issues': "SELECT pid, diagnosis, diagnosis_name, activity FROM issues WHERE pid IN (22,23,24,25,26)",
        'rx': "SELECT pid, drug_name, rxl_active FROM rx WHERE pid IN (22,23,24,25,26)",
        'encounters': "SELECT pid, encounter_date FROM encounters WHERE pid IN (22,23,24,25,26)",
    },
    'vaccine_audit_and_schedule': {
        'patients': "SELECT pid, lastname, firstname, sex, DOB FROM demographics WHERE pid IN (27,28,29,30) ORDER BY pid",
        'immunizations': "SELECT pid, imm_immunization, imm_date, imm_cvx FROM immunizations WHERE pid IN (27,28,29,30) ORDER BY pid",
        'schedule': "SELECT pid, start, visit_type FROM schedule WHERE pid IN (27,28,29,30)",
    },
    'post_visit_documentation_workflow': {
        'patient': "SELECT pid, lastname, firstname, sex, DOB FROM demographics WHERE pid=31",
        'encounters': "SELECT eid, pid, encounter_date FROM encounters WHERE pid=31",
        'vitals': "SELECT vitals_id, pid, weight, height FROM vitals WHERE pid=31",
        'issues': "SELECT pid, diagnosis, diagnosis_name FROM issues WHERE pid=31",
        'allergies': "SELECT pid, allergen, allergy_type FROM allergies WHERE pid=31",
        'rx': "SELECT pid, drug_name, rxl_dosage, rxl_active FROM rx WHERE pid=31",
        'schedule': "SELECT pid, start FROM schedule WHERE pid=31",
    },
    'allergy_drug_conflict_resolution': {
        'patients': "SELECT pid, lastname, firstname FROM demographics WHERE pid IN (32,33,34,35) ORDER BY pid",
        'allergies': "SELECT pid, allergen, allergy_type, allergy_reaction FROM allergies WHERE pid IN (32,33,34,35) ORDER BY pid",
        'rx': "SELECT pid, drug_name, rxl_dosage, rxl_active FROM rx WHERE pid IN (32,33,34,35) ORDER BY pid",
        'encounters': "SELECT pid, encounter_date FROM encounters WHERE pid IN (32,33,34,35)",
    },
    'diabetic_care_gap_intervention': {
        'patients': "SELECT pid, lastname, firstname, sex, DOB FROM demographics WHERE pid IN (36,37,38,39,40) ORDER BY pid",
        'issues': "SELECT pid, diagnosis, diagnosis_name, activity FROM issues WHERE pid IN (36,37,38,39,40) ORDER BY pid",
        'immunizations': "SELECT pid, imm_immunization, imm_date FROM immunizations WHERE pid IN (36,37,38,39,40) ORDER BY pid, imm_date",
        'encounters': "SELECT pid, encounter_date FROM encounters WHERE pid IN (36,37,38,39,40) ORDER BY pid, encounter_date",
    },
}

DB_CMD = 'docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e'


def db_query(env, sql):
    """Run a MySQL query via docker exec in the environment."""
    cmd = f"{DB_CMD} \"{sql}\""
    try:
        result = env._runner.exec_capture(cmd)
        return result.strip() if result else ""
    except Exception as e:
        return f"ERROR: {e}"


def take_screenshot(env, name):
    """Capture screenshot from environment."""
    remote_path = f'/tmp/{name}.png'
    local_path = f'{EVIDENCE_DIR}/{name}.png'
    try:
        env._runner.exec_capture(
            f'DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root {remote_path} 2>/dev/null || '
            f'DISPLAY=:1 scrot {remote_path} 2>/dev/null || echo "screenshot failed"'
        )
        time.sleep(0.5)
        env._runner.copy_from(remote_path, local_path)
        print(f"Screenshot saved: {local_path}")
        return local_path
    except Exception as e:
        print(f"Screenshot error: {e}")
        return None


def collect_evidence(env, task_name):
    """Collect DB evidence and screenshot for a task."""
    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "checks": {},
        "setup_files": {},
    }

    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    # Check Docker status
    docker_status = env._runner.exec_capture('docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null || echo "docker not available"')
    evidence["checks"]["docker_status"] = docker_status.strip()

    # Run task-specific DB queries
    queries = TASK_QUERIES.get(task_name, {})
    for query_name, sql in queries.items():
        result = db_query(env, sql)
        evidence["checks"][query_name] = result
        print(f"  [{query_name}]: {result[:200] if result else 'empty'}")

    # Check setup files
    setup_files_check = env._runner.exec_capture(f'ls -la /tmp/{task_name}_* 2>&1 || echo "no setup files"')
    evidence["setup_files"] = setup_files_check.strip()

    # Take screenshot
    screenshot_path = take_screenshot(env, f'{task_name}_start')
    if screenshot_path:
        evidence["screenshot"] = screenshot_path

    # Save evidence JSON
    evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
    with open(evidence_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    print(f"Evidence saved: {evidence_path}")

    return evidence


def run_do_nothing_test(env, task_name):
    """
    Do-nothing test: run export immediately, verify score=0 / passed=False.
    Uses env.step([], mark_done=True) per checklist.
    """
    print(f"\n[DO-NOTHING TEST] Running export for {task_name}...")

    # Run export script directly
    export_out = env._runner.exec_capture(
        f'bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1'
    )
    print(f"Export output (last 500 chars):\n{export_out[-500:]}")

    # Check export script succeeded
    if "Export complete" in export_out.lower() or "export complete" in export_out:
        print("[PASS] Export script completed")
    else:
        print("[WARN] Export may have issues (no 'Export complete' in output)")

    # Check JSON file exists
    json_check = env._runner.exec_capture(
        f'python3 -m json.tool /tmp/{task_name}_result.json 2>&1 | head -5'
    )
    if "ERROR" in json_check or "error" in json_check.lower():
        print(f"[FAIL] JSON invalid: {json_check}")
    else:
        print(f"[PASS] JSON valid")

    # Now get verifier result via env.step
    try:
        obs, reward, done, info = env.step([], mark_done=True)
        verifier_result = info.get('verifier', {})
        passed = verifier_result.get('passed', None)
        score = verifier_result.get('score', None)
        feedback = verifier_result.get('feedback', '')

        print(f"\n[VERIFIER RESULT]")
        print(f"  passed: {passed}")
        print(f"  score:  {score}")
        print(f"  feedback: {feedback[:300]}")

        if passed == False and score == 0:
            print("[PASS] Do-nothing test passed: score=0, passed=False")
        elif passed == False:
            print(f"[PARTIAL] Do-nothing test: passed=False but score={score} (acceptable if > 0 for initial state)")
        else:
            print(f"[FAIL] Do-nothing test FAILED: passed={passed}, score={score}")

        return verifier_result
    except Exception as e:
        print(f"[ERROR] Could not run verifier: {e}")
        return {}


def test_task(task_name):
    """Test a single task: boot, collect evidence, do-nothing test."""
    from gym_anything.api import from_config

    print(f"\n{'='*70}")
    print(f"TESTING: {task_name}")
    print('='*70)

    env = None
    try:
        env = from_config(ENV_NAME, task_id=task_name)
        obs = env.reset(seed=42, use_cache=False)
        print(f"Environment ready - VNC: {env._runner.vnc_port}")

        time.sleep(5)  # Let setup script finish

        evidence = collect_evidence(env, task_name)

        verifier_result = run_do_nothing_test(env, task_name)
        evidence["do_nothing_test"] = verifier_result

        # Update evidence with verifier result
        evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
        with open(evidence_path, 'w') as f:
            json.dump(evidence, f, indent=2)

        return evidence

    except ImportError as e:
        print(f"[ERROR] Could not import gym_anything: {e}")
        print("Make sure you're running from the repo root with the right Python environment.")
        return {}
    finally:
        if env is not None:
            print(f"\nClosing environment (wait ~20s for cleanup)...")
            time.sleep(20)
            env.close()


def main():
    tasks_to_test = NEW_TASKS
    if len(sys.argv) > 1:
        tasks_to_test = [sys.argv[1]]

    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    all_results = {}
    for task in tasks_to_test:
        result = test_task(task)
        all_results[task] = result

    print(f"\n{'='*70}")
    print("SUMMARY")
    print('='*70)
    for task, evidence in all_results.items():
        do_nothing = evidence.get("do_nothing_test", {})
        score = do_nothing.get("score", "N/A")
        passed = do_nothing.get("passed", "N/A")
        print(f"{task}:")
        print(f"  Do-nothing: score={score}, passed={passed}")

    print(f"\nEvidence saved to: {EVIDENCE_DIR}/")


if __name__ == "__main__":
    main()
