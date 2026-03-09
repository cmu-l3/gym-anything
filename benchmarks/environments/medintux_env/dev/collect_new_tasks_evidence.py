#!/usr/bin/env python3
"""
Evidence collection and do-nothing validation script for new medintux_env tasks.

This script:
1. Loads each new task environment
2. Runs the setup script
3. Immediately runs the export script WITHOUT any agent actions (do-nothing test)
4. Calls the verifier and verifies score=0 (do-nothing should always fail)
5. Takes a screenshot of the starting state
6. Saves evidence JSON for each task

Usage:
    python3 benchmarks/environments/medintux_env/dev/collect_new_tasks_evidence.py

Or for a specific task:
    python3 benchmarks/environments/medintux_env/dev/collect_new_tasks_evidence.py polypharmacy_review_and_update
"""

import sys
import os
import time
import json
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')

EVIDENCE_DIR = 'benchmarks/environments/medintux_env/evidence'
ENV_NAME = 'medintux_env'
NEW_TASKS = [
    'polypharmacy_review_and_update',
    'overdue_followup_scheduling',
    'new_patient_complex_entry',
    'medical_correspondence_batch',
    'chronic_panel_audit',
]


def collect_evidence(env, task_name):
    """Collect evidence for a single task."""
    evidence = {
        'task': task_name,
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'checks': {},
        'do_nothing_test': {},
    }

    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    print(f'\n[SETUP] Verifying task setup files for {task_name}...')
    setup_files = env._runner.exec_capture(
        'ls -la /tmp/task_start_timestamp /tmp/baseline_* /tmp/correspondence_baseline.json '
        '/tmp/audit_baseline.json 2>&1 | head -20'
    )
    evidence['checks']['setup_files'] = setup_files.strip()
    print(setup_files[:400])

    print(f'\n[DB] Verifying target data in DrTuxTest...')
    db_check = env._runner.exec_capture(
        "mysql -u root DrTuxTest -N -e \"SELECT FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type "
        "FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier' ORDER BY FchGnrl_NomDos LIMIT 25;\" 2>/dev/null"
    )
    evidence['checks']['patients'] = db_check.strip()
    print(f'Found {len(db_check.splitlines())} patients')

    print(f'\n[SCREENSHOT] Taking starting screenshot...')
    env._runner.exec_capture('DISPLAY=:1 import -window root /tmp/evidence_start.png 2>/dev/null || true')
    time.sleep(1)
    screenshot_path = f'{EVIDENCE_DIR}/{task_name}_screenshot.png'
    try:
        env._runner.copy_from('/tmp/evidence_start.png', screenshot_path)
        evidence['screenshot'] = screenshot_path
        print(f'Screenshot saved: {screenshot_path}')
    except Exception as e:
        print(f'Screenshot error: {e}')

    print(f'\n[EXPORT] Running export script (do-nothing test)...')
    export_out = env._runner.exec_capture(
        f'bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1'
    )
    evidence['checks']['export_output'] = export_out[-2000:].strip()

    if 'Export Complete' in export_out:
        print('[PASS] Export script completed successfully')
    else:
        print('[WARN] Export may have issues:')
        print(export_out[-500:])

    # Read result JSON
    result_file_map = {
        'polypharmacy_review_and_update': '/tmp/polypharmacy_result.json',
        'overdue_followup_scheduling': '/tmp/overdue_followup_result.json',
        'new_patient_complex_entry': '/tmp/new_patient_result.json',
        'medical_correspondence_batch': '/tmp/correspondence_result.json',
        'chronic_panel_audit': '/tmp/audit_result.json',
    }
    result_path = result_file_map.get(task_name)
    if result_path:
        result_json_str = env._runner.exec_capture(f'cat {result_path} 2>/dev/null || echo "FILE_NOT_FOUND"')
        evidence['checks']['result_json'] = result_json_str[:2000]
        try:
            result_data = json.loads(result_json_str)
            evidence['checks']['result_parsed'] = True
            print(f'Result JSON parsed successfully ({len(result_json_str)} bytes)')
        except Exception as e:
            evidence['checks']['result_parsed'] = False
            evidence['checks']['result_parse_error'] = str(e)
            print(f'[WARN] Result JSON parse error: {e}')

    # Run do-nothing verification
    print(f'\n[VERIFY] Running do-nothing verification...')
    try:
        obs, reward, done, info = env.step([], mark_done=True)
        verifier_result = info.get('verifier', {})
        evidence['do_nothing_test'] = {
            'score': verifier_result.get('score', -1),
            'passed': verifier_result.get('passed', None),
            'feedback': verifier_result.get('feedback', '')[:500],
        }
        score = verifier_result.get('score', -1)
        passed = verifier_result.get('passed', None)
        if score == 0 and passed is False:
            print(f'[PASS] Do-nothing test: score={score}, passed={passed} (expected 0/False)')
        else:
            print(f'[WARN] Do-nothing test: score={score}, passed={passed} (expected 0/False!)')
            print(f'  Feedback: {verifier_result.get("feedback","")[:300]}')
    except Exception as e:
        print(f'[WARN] Verification error: {e}')
        evidence['do_nothing_test']['error'] = str(e)

    evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
    with open(evidence_path, 'w') as f:
        json.dump(evidence, f, indent=2, default=str)
    print(f'\nEvidence saved: {evidence_path}')

    return evidence


def test_task(task_name):
    """Test a single task and collect evidence."""
    from gym_anything.api import from_config

    print(f'\n{"="*65}')
    print(f'TESTING: {task_name}')
    print('='*65)

    env = from_config(f'benchmarks/environments/{ENV_NAME}', task_id=task_name)

    try:
        print(f'Loading environment (use_cache=True for faster startup)...')
        obs = env.reset(seed=42, use_cache=True, use_savevm=True)
        print(f'Environment ready — VNC: {getattr(env._runner, "vnc_port", "?")}, '
              f'SSH: {getattr(env._runner, "ssh_port", "?")}')

        return collect_evidence(env, task_name)

    except Exception as e:
        print(f'[ERROR] Task {task_name} failed: {e}')
        import traceback
        traceback.print_exc()
        return {'task': task_name, 'error': str(e)}

    finally:
        try:
            env.close()
        except Exception:
            pass


def main():
    tasks = sys.argv[1:] if len(sys.argv) > 1 else NEW_TASKS

    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    all_results = {}
    for task in tasks:
        result = test_task(task)
        all_results[task] = result

    print(f'\n{"="*65}')
    print('EVIDENCE COLLECTION SUMMARY')
    print('='*65)
    for task, evidence in all_results.items():
        if 'error' in evidence:
            print(f'{task}: ERROR - {evidence["error"]}')
            continue
        do_nothing = evidence.get('do_nothing_test', {})
        score = do_nothing.get('score', '?')
        passed = do_nothing.get('passed', '?')
        status = 'OK' if score == 0 and passed is False else 'WARN'
        print(f'{task}: [{status}] do-nothing score={score}, passed={passed}')

    print(f'\nAll evidence in: {EVIDENCE_DIR}/')


if __name__ == '__main__':
    main()
