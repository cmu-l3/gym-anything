#!/usr/bin/env python3
"""
Evidence collection and live testing for bluemail_env new tasks.
Tests: mailing_list_triage, spam_infiltration_response, vendor_patch_escalation,
       project_inbox_zero, domain_analysis_and_reporting

Usage:
    python3 benchmarks/environments/bluemail_env/dev/collect_evidence.py [task_name]
    python3 benchmarks/environments/bluemail_env/dev/collect_evidence.py all
"""

import sys
import os
import time
import json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')
from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/environments/bluemail_env/evidence'
ENV_PATH = 'benchmarks/environments/bluemail_env'

NEW_TASKS = [
    'mailing_list_triage',
    'spam_infiltration_response',
    'vendor_patch_escalation',
    'project_inbox_zero',
    'domain_analysis_and_reporting',
]


def collect_evidence(env, task_name):
    """Collect comprehensive evidence for a task after env.reset()."""
    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "checks": {}
    }

    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    # 1. Verify setup files were created
    print(f"\n[SETUP] Checking /tmp setup files for {task_name}...")
    setup_files_out = env._runner.exec_capture(
        'ls -la /tmp/initial_* /tmp/task_start_timestamp /tmp/task_start_screenshot.png 2>&1'
    )
    evidence["checks"]["setup_files"] = setup_files_out.strip()
    print(setup_files_out)

    # 2. Read baseline values
    print(f"\n[BASELINE] Reading baseline state...")
    baseline_out = env._runner.exec_capture(
        'for f in /tmp/initial_*; do echo "$f: $(cat $f 2>/dev/null)"; done'
    )
    evidence["checks"]["baseline_values"] = baseline_out.strip()
    print(baseline_out)

    # 3. Check Maildir state
    print(f"\n[MAILDIR] Checking Maildir state...")
    maildir_out = env._runner.exec_capture(
        'ls /home/ga/Maildir/ && echo "--- inbox count:" && ls /home/ga/Maildir/cur/ 2>/dev/null | wc -l'
    )
    evidence["checks"]["maildir_state"] = maildir_out.strip()
    print(maildir_out)

    # 4. Check BlueMail running
    print(f"\n[BLUEMAIL] Checking BlueMail process...")
    bm_out = env._runner.exec_capture('pgrep -l bluemail 2>/dev/null || echo "BlueMail not running"')
    evidence["checks"]["bluemail_running"] = bm_out.strip()
    print(bm_out)

    # 5. For domain_analysis_and_reporting: check top domains file
    if task_name == 'domain_analysis_and_reporting':
        print(f"\n[DOMAINS] Checking top sender domains file...")
        domains_out = env._runner.exec_capture(
            'cat /tmp/top_sender_domains.json 2>/dev/null || echo "File not found"'
        )
        evidence["checks"]["top_sender_domains"] = domains_out.strip()
        print(domains_out[:500])

    # 6. Copy start screenshot
    screenshot_dst = f'{EVIDENCE_DIR}/{task_name}_screenshot.png'
    try:
        env._runner.copy_from('/tmp/task_start_screenshot.png', screenshot_dst)
        evidence["screenshot"] = screenshot_dst
        print(f"\n[SCREENSHOT] Saved: {screenshot_dst}")
    except Exception as e:
        print(f"\n[SCREENSHOT] Failed to copy: {e}")
        evidence["screenshot"] = f"ERROR: {e}"

    # 7. Save evidence JSON
    evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
    with open(evidence_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    print(f"[EVIDENCE] Saved: {evidence_path}")

    return evidence


def test_export_script(env, task_name):
    """Test that export script runs without errors and produces valid JSON."""
    print(f"\n[EXPORT] Running export script for {task_name}...")
    export_out = env._runner.exec_capture(
        f'bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1'
    )
    print(export_out[-2000:])

    export_ok = "Export Complete" in export_out

    # Verify JSON is valid
    json_check = env._runner.exec_capture(
        'python3 -m json.tool /tmp/task_result.json 2>&1 | head -5 || echo "JSON INVALID"'
    )
    json_valid = "JSON INVALID" not in json_check and "Error" not in json_check

    # Get JSON contents
    result_json = env._runner.exec_capture('cat /tmp/task_result.json 2>/dev/null')

    print(f"\n[EXPORT] Complete: {export_ok}, JSON valid: {json_valid}")
    print(f"[EXPORT] Result JSON (truncated):\n{result_json[:800]}")

    return {
        "export_script_ok": export_ok,
        "result_json_valid": json_valid,
        "result_json_snippet": result_json[:500]
    }


def test_do_nothing_verifier(env, task_name):
    """Run do-nothing test: export immediately, check score=0."""
    print(f"\n[VERIFY] Running do-nothing verifier test for {task_name}...")
    # env.step([], mark_done=True) runs post_task hook then calls verifier
    obs, reward, done, info = env.step([], mark_done=True)
    result = info.get("verifier", {})
    score = result.get("score", -1)
    passed = result.get("passed", None)
    feedback = result.get("feedback", "")
    print(f"[VERIFY] score={score}, passed={passed}")
    print(f"[VERIFY] feedback={feedback}")

    ok = (score == 0 and passed is False)
    if ok:
        print(f"[VERIFY] PASS: Do-nothing correctly returns score=0")
    else:
        print(f"[VERIFY] FAIL: Expected score=0/passed=False, got score={score}/passed={passed}")

    return {
        "score": score,
        "passed": passed,
        "feedback": feedback,
        "do_nothing_ok": ok
    }


def test_task(task_name, use_cache=True):
    """Full test for a single task: reset, evidence, export, do-nothing verify."""
    print(f"\n{'='*70}")
    print(f"TESTING: {task_name}")
    print('='*70)

    env = from_config(ENV_PATH, task_id=task_name)
    all_results = {"task": task_name}

    try:
        print(f"\n[RESET] Starting environment (use_cache={use_cache})...")
        t0 = time.time()
        obs = env.reset(seed=42, use_cache=use_cache)
        elapsed = time.time() - t0
        print(f"[RESET] Environment ready in {elapsed:.1f}s")
        all_results["reset_ok"] = True
        all_results["reset_time_sec"] = round(elapsed, 1)

        # Collect evidence
        evidence = collect_evidence(env, task_name)
        all_results["evidence"] = evidence

        # Test export script
        export_result = test_export_script(env, task_name)
        all_results["export_test"] = export_result

        # Do-nothing verifier
        verify_result = test_do_nothing_verifier(env, task_name)
        all_results["do_nothing_test"] = verify_result

        all_results["overall_ok"] = (
            export_result["export_script_ok"] and
            export_result["result_json_valid"] and
            verify_result["do_nothing_ok"]
        )

    except Exception as e:
        print(f"[ERROR] Task {task_name} failed: {e}")
        import traceback
        traceback.print_exc()
        all_results["error"] = str(e)
        all_results["overall_ok"] = False

    finally:
        print(f"\n[CLOSE] Closing environment...")
        env.close()

    return all_results


def main():
    tasks_to_test = sys.argv[1:] if len(sys.argv) > 1 else ['all']

    if tasks_to_test == ['all']:
        tasks_to_test = NEW_TASKS

    print(f"\nBlueMail Evidence Collection & Testing")
    print(f"Tasks: {tasks_to_test}")
    print(f"Evidence dir: {EVIDENCE_DIR}")

    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    all_summary = {}
    for task in tasks_to_test:
        if task not in NEW_TASKS:
            print(f"[WARN] Unknown task: {task}. Valid: {NEW_TASKS}")
            continue
        result = test_task(task)
        all_summary[task] = result

    # Print summary
    print(f"\n\n{'='*70}")
    print("SUMMARY")
    print('='*70)
    for task, result in all_summary.items():
        ok = result.get("overall_ok", False)
        status = "PASS" if ok else "FAIL"
        export_ok = result.get("export_test", {}).get("export_script_ok", "?")
        json_ok = result.get("export_test", {}).get("result_json_valid", "?")
        verify_ok = result.get("do_nothing_test", {}).get("do_nothing_ok", "?")
        score = result.get("do_nothing_test", {}).get("score", "?")
        print(f"  [{status}] {task}: export={export_ok}, json={json_ok}, do_nothing_score={score}, verify={verify_ok}")

    # Save overall summary
    summary_path = f'{EVIDENCE_DIR}/test_summary.json'
    with open(summary_path, 'w') as f:
        json.dump(all_summary, f, indent=2, default=str)
    print(f"\nFull summary: {summary_path}")


if __name__ == "__main__":
    main()
