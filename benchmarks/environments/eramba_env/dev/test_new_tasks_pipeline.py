#!/usr/bin/env python3
"""Phase 4+5 pipeline test for eramba_env new tasks.

Tests:
  - Do-nothing (live VM): score=0, passed=False for each task
  - Partial completion (DB injection): score partial, passed=False
  - Evidence collection: screenshots + JSON saved to evidence/

Usage:
  GYM_ANYTHING_QEMU_WORK_DIR=/tmp/qemu_work python3 benchmarks/environments/eramba_env/dev/test_new_tasks_pipeline.py
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')
from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/environments/eramba_env/evidence'
ENV_PATH = 'benchmarks/environments/eramba_env'

NEW_TASKS = [
    'hipaa_risk_treatment_program',
    'pci_dss_gap_remediation',
    'vendor_risk_management_program',
    'ransomware_incident_postmortem',
    'annual_policy_review_cycle',
]

# Partial injection SQL for each task:
# Insert just enough to get 20-60 pts but not pass (>=60).
# Uses minimal required fields discovered from live DB.
PARTIAL_INJECTIONS = {
    'hipaa_risk_treatment_program': [
        # 3 new risks with treatment (24 pts) — not enough to pass
        "INSERT INTO risks (title, description, risk_mitigation_strategy_id, status, deleted, created, modified) VALUES ('PHI Unauthorized Access Risk', 'External attacker gains access to PHI', 3, 1, 0, NOW(), NOW());",
        "INSERT INTO risks (title, description, risk_mitigation_strategy_id, status, deleted, created, modified) VALUES ('Ransomware Clinical Disruption Risk', 'Ransomware encrypts clinical systems', 3, 1, 0, NOW(), NOW());",
        "INSERT INTO risks (title, description, risk_mitigation_strategy_id, status, deleted, created, modified) VALUES ('PHI Improper Disposal Risk', 'PHI improperly disposed or transmitted', 2, 1, 0, NOW(), NOW());",
    ],
    'pci_dss_gap_remediation': [
        # 3 Mitigate risks (19 pts) — not enough to pass
        "INSERT INTO risks (title, description, risk_mitigation_strategy_id, status, deleted, created, modified) VALUES ('Firewall Misconfiguration Risk', 'PCI Req 1.2 - Firewall rules not documented', 3, 1, 0, NOW(), NOW());",
        "INSERT INTO risks (title, description, risk_mitigation_strategy_id, status, deleted, created, modified) VALUES ('PAN Unencrypted Storage Risk', 'PCI Req 3.4 - PANs stored without encryption', 3, 1, 0, NOW(), NOW());",
        "INSERT INTO risks (title, description, risk_mitigation_strategy_id, status, deleted, created, modified) VALUES ('Vulnerability Scan Gap Risk', 'PCI Req 6.3 - No quarterly external scans', 3, 1, 0, NOW(), NOW());",
    ],
    'vendor_risk_management_program': [
        # 3 new vendors (23 pts) + 0 risks — not enough to pass
        "INSERT INTO third_parties (name, description, deleted, created, modified) VALUES ('Microsoft Azure', 'Cloud infrastructure vendor', 0, NOW(), NOW());",
        "INSERT INTO third_parties (name, description, deleted, created, modified) VALUES ('Okta Inc', 'Identity provider vendor', 0, NOW(), NOW());",
        "INSERT INTO third_parties (name, description, deleted, created, modified) VALUES ('Crowdstrike Holdings', 'Endpoint security vendor', 0, NOW(), NOW());",
    ],
    'ransomware_incident_postmortem': [
        # 1 incident (20 pts) + 0 risks — not enough to pass
        "INSERT INTO security_incidents (title, description, status, deleted, created, modified) VALUES ('LockBit 3.0 Ransomware Attack', 'Ransomware incident via unpatched VPN', 1, 0, NOW(), NOW());",
    ],
    'annual_policy_review_cycle': [
        # 3 new policies (21 pts) — not enough to pass
        "INSERT INTO security_policies (`index`, description, status, deleted, created, modified) VALUES ('Information Security Policy', 'Core IS policy', 1, 0, NOW(), NOW());",
        "INSERT INTO security_policies (`index`, description, status, deleted, created, modified) VALUES ('Access Control Policy', 'User access control policy', 0, 0, NOW(), NOW());",
        "INSERT INTO security_policies (`index`, description, status, deleted, created, modified) VALUES ('Incident Response Policy', 'IR procedures policy', 0, 0, NOW(), NOW());",
    ],
}


def mysql(runner, sql):
    """Run a MySQL query in the eramba-db container."""
    return runner.exec_capture(
        f'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "{sql}" 2>/dev/null'
    )


def collect_db_evidence(runner):
    """Collect current DB state as evidence."""
    evidence = {}
    tables = ['risks', 'security_services', 'security_policies', 'third_parties',
              'projects', 'policy_exceptions', 'security_incidents', 'assets']
    for table in tables:
        count = runner.exec_capture(
            f'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
            f'"SELECT COUNT(*) FROM {table};" 2>/dev/null'
        )
        evidence[f'{table}_count'] = (count or '').strip()
    return evidence


def test_task_do_nothing(task_name):
    """Run do-nothing test: env.reset + env.step([], mark_done=True) without any actions."""
    print(f"\n{'='*60}")
    print(f"DO-NOTHING TEST: {task_name}")
    print('='*60)

    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "env_loaded": False,
        "setup_ran": False,
        "do_nothing_score": None,
        "do_nothing_passed": None,
        "do_nothing_test_pass": False,
        "errors": []
    }

    env = None
    try:
        env = from_config(ENV_PATH, task_id=task_name)
        print(f"  Loading env with post_start checkpoint...")
        obs = env.reset(seed=42, use_cache=True, use_savevm=True)
        evidence["env_loaded"] = True
        print(f"  Env loaded. VNC: {env._runner.vnc_port}")

        # Check setup ran
        baseline_file = f'/tmp/{task_name}_baseline.txt'
        baseline_content = env._runner.exec_capture(f'cat {baseline_file} 2>/dev/null')
        if baseline_content and baseline_content.strip():
            evidence["setup_ran"] = True
            evidence["baseline"] = baseline_content.strip()
            print(f"  Setup ran. Baseline: {baseline_content.strip()[:200]}")
        else:
            evidence["errors"].append("setup: baseline file missing")
            print(f"  WARN: Baseline file missing at {baseline_file}")

        # Collect initial DB state
        evidence["initial_db_state"] = collect_db_evidence(env._runner)
        print(f"  DB state: {evidence['initial_db_state']}")

        # Take screenshot
        screenshot_path = f'/tmp/{task_name}_do_nothing_screenshot.png'
        env._runner.exec_capture(f'DISPLAY=:1 scrot {screenshot_path} 2>/dev/null || true')
        time.sleep(1)
        try:
            local_path = f'{EVIDENCE_DIR}/{task_name}_screenshot.png'
            env._runner.copy_from(screenshot_path, local_path)
            evidence["screenshot"] = local_path
            print(f"  Screenshot saved: {local_path}")
        except Exception as e:
            evidence["errors"].append(f"screenshot: {e}")
            print(f"  Screenshot error: {e}")

        # Do-nothing test
        print(f"  Running do-nothing step...")
        obs, reward, done, info = env.step([], mark_done=True)
        result = info.get("verifier", {})
        score = result.get("score", -1)
        passed = result.get("passed", None)
        feedback = result.get("feedback", "")

        evidence["do_nothing_score"] = score
        evidence["do_nothing_passed"] = passed
        evidence["do_nothing_feedback"] = feedback
        evidence["do_nothing_test_pass"] = (score == 0 and passed == False)

        print(f"  Do-nothing result: score={score}, passed={passed}")
        print(f"  Feedback: {feedback}")

        if evidence["do_nothing_test_pass"]:
            print(f"  ✓ DO-NOTHING TEST PASSED (score=0, passed=False)")
        else:
            print(f"  ✗ DO-NOTHING TEST FAILED (expected score=0/passed=False, got score={score}/passed={passed})")
            evidence["errors"].append(f"do_nothing: expected score=0/passed=False, got score={score}/passed={passed}")

    except Exception as e:
        import traceback
        evidence["errors"].append(f"exception: {str(e)}")
        print(f"  ERROR: {e}")
        traceback.print_exc()
    finally:
        if env:
            try:
                env.close()
            except Exception:
                pass

    return evidence


def test_task_partial(task_name):
    """Run partial completion test: inject some DB records, then verify score is partial."""
    print(f"\n{'='*60}")
    print(f"PARTIAL TEST: {task_name}")
    print('='*60)

    partial_evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "partial_score": None,
        "partial_passed": None,
        "partial_test_pass": False,
        "injected_sqls": PARTIAL_INJECTIONS.get(task_name, []),
        "errors": []
    }

    injections = PARTIAL_INJECTIONS.get(task_name, [])
    if not injections:
        print(f"  No partial injection defined for {task_name}, skipping")
        partial_evidence["errors"].append("no_partial_injection_defined")
        return partial_evidence

    env = None
    try:
        env = from_config(ENV_PATH, task_id=task_name)
        print(f"  Loading env...")
        obs = env.reset(seed=42, use_cache=True, use_savevm=True)
        print(f"  Env loaded.")

        # Wait for setup to complete
        time.sleep(2)

        # Inject partial records
        for sql in injections:
            result = env._runner.exec_capture(
                f'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e "{sql}" 2>&1'
            )
            print(f"  Injected: {sql[:80]}... result: {(result or '').strip()[:80]}")

        print(f"  Injected {len(injections)} records. Running verifier...")

        # Run verifier
        obs, reward, done, info = env.step([], mark_done=True)
        result = info.get("verifier", {})
        score = result.get("score", -1)
        passed = result.get("passed", None)
        feedback = result.get("feedback", "")

        partial_evidence["partial_score"] = score
        partial_evidence["partial_passed"] = passed
        partial_evidence["partial_feedback"] = feedback
        partial_evidence["partial_test_pass"] = (score > 0 and score < 60 and passed == False)

        print(f"  Partial result: score={score}, passed={passed}")
        print(f"  Feedback: {feedback}")

        if partial_evidence["partial_test_pass"]:
            print(f"  ✓ PARTIAL TEST PASSED (score={score} in (0,60), passed=False)")
        else:
            print(f"  ✗ PARTIAL TEST RESULT: score={score}, passed={passed} (expected 0<score<60, passed=False)")
            if score >= 60:
                partial_evidence["errors"].append(f"partial_too_high: score={score} >= 60")
            elif score == 0:
                partial_evidence["errors"].append(f"partial_zero: injection may have failed or schema mismatch")

    except Exception as e:
        import traceback
        partial_evidence["errors"].append(f"exception: {str(e)}")
        print(f"  ERROR: {e}")
        traceback.print_exc()
    finally:
        if env:
            try:
                env.close()
            except Exception:
                pass

    return partial_evidence


def discover_schema(task_name):
    """Discover the DB schema for key tables by running DESCRIBE queries."""
    print(f"\n{'='*60}")
    print(f"SCHEMA DISCOVERY (for partial injection debugging)")
    print('='*60)

    schema = {}
    env = None
    try:
        env = from_config(ENV_PATH, task_id=task_name)
        obs = env.reset(seed=42, use_cache=True, use_savevm=True)
        time.sleep(2)

        for table in ['risks', 'security_services', 'security_policies', 'third_parties',
                      'projects', 'policy_exceptions', 'security_incidents', 'assets']:
            result = env._runner.exec_capture(
                f'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
                f'"DESCRIBE {table};" 2>/dev/null'
            )
            schema[table] = (result or '').strip()
            print(f"\n  {table}:\n{(result or '').strip()[:500]}")

    except Exception as e:
        print(f"  Schema discovery error: {e}")
    finally:
        if env:
            try:
                env.close()
            except Exception:
                pass

    return schema


def main():
    os.makedirs(EVIDENCE_DIR, exist_ok=True)
    os.makedirs('/tmp/qemu_work', exist_ok=True)

    print("=" * 70)
    print("ERAMBA ENV NEW TASKS - PHASE 4+5 PIPELINE TEST")
    print("=" * 70)
    print(f"Tasks: {NEW_TASKS}")
    print(f"Evidence dir: {EVIDENCE_DIR}")

    # First: discover schema from the first task env to verify partial injection SQL
    print("\n>>> PHASE 0: SCHEMA DISCOVERY (run first to validate partial injection SQL) <<<")
    schema = discover_schema(NEW_TASKS[0])
    schema_path = f'{EVIDENCE_DIR}/db_schema_discovery.json'
    with open(schema_path, 'w') as f:
        json.dump(schema, f, indent=2)
    print(f"\nSchema saved to {schema_path}")

    all_results = {}

    # Phase 4: Do-nothing tests
    print("\n>>> PHASE 4: DO-NOTHING VM TESTS <<<")
    for task_name in NEW_TASKS:
        evidence = test_task_do_nothing(task_name)
        all_results[task_name] = {"do_nothing": evidence}

        # Save individual evidence
        evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
        with open(evidence_path, 'w') as f:
            json.dump(evidence, f, indent=2)
        print(f"  Evidence saved: {evidence_path}")

    # Phase 5: Partial completion tests
    print("\n>>> PHASE 5: PARTIAL COMPLETION TESTS <<<")
    for task_name in NEW_TASKS:
        partial_ev = test_task_partial(task_name)
        all_results[task_name]["partial"] = partial_ev

        # Update evidence file
        evidence_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
        try:
            with open(evidence_path) as f:
                existing = json.load(f)
        except Exception:
            existing = {}
        existing["partial_test"] = partial_ev
        with open(evidence_path, 'w') as f:
            json.dump(existing, f, indent=2)

    # Summary
    print("\n" + "=" * 70)
    print("TEST SUMMARY")
    print("=" * 70)

    all_do_nothing_pass = True
    all_partial_reasonable = True
    summary = {}

    for task_name in NEW_TASKS:
        dn = all_results[task_name]["do_nothing"]
        pt = all_results[task_name]["partial"]
        dn_ok = dn.get("do_nothing_test_pass", False)
        pt_ok = pt.get("partial_test_pass", False)

        if not dn_ok:
            all_do_nothing_pass = False

        summary[task_name] = {
            "do_nothing_score": dn.get("do_nothing_score"),
            "do_nothing_passed": dn.get("do_nothing_passed"),
            "do_nothing_ok": dn_ok,
            "partial_score": pt.get("partial_score"),
            "partial_passed": pt.get("partial_passed"),
            "partial_ok": pt_ok,
            "errors": dn.get("errors", []) + pt.get("errors", [])
        }

        status = "✓" if dn_ok else "✗"
        partial_status = "✓" if pt_ok else "?"
        print(f"  {status} {task_name}")
        print(f"    do-nothing: score={dn.get('do_nothing_score')}, passed={dn.get('do_nothing_passed')} [{status}]")
        print(f"    partial:    score={pt.get('partial_score')}, passed={pt.get('partial_passed')} [{partial_status}]")
        if summary[task_name]["errors"]:
            print(f"    errors: {summary[task_name]['errors']}")

    print(f"\nAll do-nothing return score=0, passed=False: {all_do_nothing_pass}")

    # Save summary
    summary_path = f'{EVIDENCE_DIR}/new_tasks_test_summary.json'
    with open(summary_path, 'w') as f:
        json.dump(summary, f, indent=2)
    print(f"\nSummary saved: {summary_path}")

    return 0 if all_do_nothing_pass else 1


if __name__ == "__main__":
    sys.exit(main())
