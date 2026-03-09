#!/usr/bin/env python3
"""Targeted re-test script for eramba_env new tasks (Phase 4+5).

Fixes applied:
  1. exec_capture fallback in all verifiers (done in verifier.py files)
  2. Backtick escaping for `index` column (done in verifier.py files)
  3. Correct schema for partial injection SQL (done here)
  4. Backtick escaping in partial injection SQL for `index` column

Re-tests:
  - Do-nothing for vendor (was 20 due to backtick bug), hipaa (was 0 for wrong reason), pci (same)
  - All 5 partial completion tests with correct schema SQL

Usage:
  GYM_ANYTHING_QEMU_WORK_DIR=/tmp/qemu_work python3 benchmarks/environments/eramba_env/dev/test_targeted_pipeline.py
"""

import base64
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')
from gym_anything.api import from_config

EVIDENCE_DIR = 'benchmarks/environments/eramba_env/evidence'
ENV_PATH = 'benchmarks/environments/eramba_env'

# Tasks needing do-nothing re-test (others already confirmed):
RETEST_DO_NOTHING = [
    'vendor_risk_management_program',   # was 20 due to backtick false positive
    'hipaa_risk_treatment_program',     # was 0 for wrong reason (exec_capture was None)
    'pci_dss_gap_remediation',          # was 0 for wrong reason (exec_capture was None)
]

ALL_TASKS = [
    'hipaa_risk_treatment_program',
    'pci_dss_gap_remediation',
    'vendor_risk_management_program',
    'ransomware_incident_postmortem',
    'annual_policy_review_cycle',
]

# Correct schema from live DB (db_schema_discovery.json):
#
# risks: NOT NULL without default = threats(text), vulnerabilities(text),
#        residual_score(int), risk_score_formula(text), residual_risk(float),
#        residual_risk_formula(text), review(date), created(datetime), modified(datetime)
#
# security_incidents: NOT NULL without default = title, description, reporter,
#        victim, open_date(date), type(varchar), created, modified
#
# security_policies: NOT NULL without default = index(varchar), short_description,
#        document_type, version, published_date(date), next_review_date(date),
#        permission, status(int), created, modified
#   NOTE: `index` is MySQL reserved word — use \\`index\\` in Python string
#         so shell sees \`index\` inside double-quotes = escaped literal backtick
#
# third_parties: NOT NULL = name, description, created, modified
#        (security_incident_count etc. have default 0)
#
# policy_exceptions: NOT NULL without default = title, description, expiration(date),
#        status(int), created, modified

PARTIAL_INJECTIONS = {
    'hipaa_risk_treatment_program': [
        # 3 new risks with treatment strategy (gives ~24 pts for risk criterion,
        # but NOT enough to pass since policy/controls/project are still missing)
        ("INSERT INTO risks "
         "(title, threats, vulnerabilities, residual_score, risk_score_formula, "
         "residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, "
         "deleted, created, modified) VALUES "
         "('PHI Unauthorized Access Risk', 'External attacker via compromised credentials', "
         "'Weak MFA on EHR system', 75, 'High*High', 30.0, 'Residual after controls', "
         "'2025-12-31', 3, 0, NOW(), NOW());"),
        ("INSERT INTO risks "
         "(title, threats, vulnerabilities, residual_score, risk_score_formula, "
         "residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, "
         "deleted, created, modified) VALUES "
         "('Ransomware Clinical Disruption Risk', 'Ransomware operator via phishing', "
         "'Unpatched legacy clinical systems', 80, 'High*High', 40.0, "
         "'Residual after backups', '2025-12-31', 3, 0, NOW(), NOW());"),
        ("INSERT INTO risks "
         "(title, threats, vulnerabilities, residual_score, risk_score_formula, "
         "residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, "
         "deleted, created, modified) VALUES "
         "('PHI Improper Disposal Risk', 'Internal staff via negligence', "
         "'No media sanitization procedures', 60, 'Medium*High', 20.0, "
         "'Residual after training', '2025-12-31', 2, 0, NOW(), NOW());"),
    ],
    'pci_dss_gap_remediation': [
        # 3 new Mitigate risks (gives ~22 pts for risk criterion, not enough to pass)
        ("INSERT INTO risks "
         "(title, threats, vulnerabilities, residual_score, risk_score_formula, "
         "residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, "
         "deleted, created, modified) VALUES "
         "('Firewall Misconfiguration Risk', 'External attacker via exposed ports', "
         "'Undocumented firewall rules PCI Req 1.2', 75, 'High*High', 35.0, "
         "'Residual after quarterly review', '2025-12-31', 3, 0, NOW(), NOW());"),
        ("INSERT INTO risks "
         "(title, threats, vulnerabilities, residual_score, risk_score_formula, "
         "residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, "
         "deleted, created, modified) VALUES "
         "('PAN Unencrypted Storage Risk', 'Insider threat via DB access', "
         "'PANs in plaintext PCI Req 3.4', 80, 'High*Medium', 30.0, "
         "'Residual after encryption', '2025-12-31', 3, 0, NOW(), NOW());"),
        ("INSERT INTO risks "
         "(title, threats, vulnerabilities, residual_score, risk_score_formula, "
         "residual_risk, residual_risk_formula, review, risk_mitigation_strategy_id, "
         "deleted, created, modified) VALUES "
         "('Vulnerability Scan Gap Risk', 'Attacker via unpatched systems', "
         "'No quarterly external ASV scans PCI Req 6.3', 70, 'High*Medium', 25.0, "
         "'Residual after ASV program', '2025-12-31', 3, 0, NOW(), NOW());"),
    ],
    'vendor_risk_management_program': [
        # 3 new vendors (22 pts for vendor criterion), 0 risks — not enough to pass
        ("INSERT INTO third_parties (name, description, deleted, created, modified) "
         "VALUES ('Microsoft Azure', 'Cloud infrastructure and compute services', "
         "0, NOW(), NOW());"),
        ("INSERT INTO third_parties (name, description, deleted, created, modified) "
         "VALUES ('Okta Inc', 'Identity provider and SSO vendor', 0, NOW(), NOW());"),
        ("INSERT INTO third_parties (name, description, deleted, created, modified) "
         "VALUES ('Crowdstrike Holdings', 'Endpoint detection and response vendor', "
         "0, NOW(), NOW());"),
    ],
    'ransomware_incident_postmortem': [
        # 1 ransomware security incident (20 pts), not enough to pass
        ("INSERT INTO security_incidents "
         "(title, description, reporter, victim, open_date, type, "
         "deleted, created, modified) VALUES "
         "('LockBit 3.0 Ransomware Attack', "
         "'Ransomware encrypted file servers via unpatched VPN gateway', "
         "'Security Operations Team', 'Finance and Operations Department', "
         "'2025-01-15', 'Malware', 0, NOW(), NOW());"),
    ],
    'annual_policy_review_cycle': [
        # 3 new policies: 2 Approved + 1 Draft (21 pts for policy criterion, not enough)
        # NOTE: `index` is a MySQL reserved word — safe here because mysql_inject()
        # uses base64 encoding, so backticks pass through safely to MySQL.
        ("INSERT INTO security_policies "
         "(`index`, short_description, document_type, version, "
         "published_date, next_review_date, permission, status, "
         "deleted, created, modified) VALUES "
         "('Information Security Policy', 'Core information security policy', "
         "'Policy', '2.0', '2024-01-01', '2025-01-01', 'All Staff', 1, 0, NOW(), NOW());"),
        ("INSERT INTO security_policies "
         "(`index`, short_description, document_type, version, "
         "published_date, next_review_date, permission, status, "
         "deleted, created, modified) VALUES "
         "('Access Control Policy', 'Governs user access and permissions', "
         "'Policy', '1.5', '2024-01-01', '2025-01-01', 'IT Staff', 0, 0, NOW(), NOW());"),
        ("INSERT INTO security_policies "
         "(`index`, short_description, document_type, version, "
         "published_date, next_review_date, permission, status, "
         "deleted, created, modified) VALUES "
         "('Incident Response Policy', 'IR procedures and escalation paths', "
         "'Policy', '1.2', '2024-01-01', '2025-01-01', 'Security Team', 0, 0, NOW(), NOW());"),
    ],
}


def mysql_inject(runner, sql):
    """Run MySQL injection SQL safely using base64 encoding.

    Base64-encodes the SQL so no special shell characters (backticks, quotes, etc.)
    can cause issues when the command goes through SSH/bash.
    """
    sql_b64 = base64.b64encode(sql.encode('utf-8')).decode('ascii')
    # base64 string is alphanumeric + /+= only — safe to embed in double-quoted shell string
    result = runner.exec_capture(
        f'echo "{sql_b64}" | base64 -d | '
        f'docker exec -i eramba-db mysql -u eramba -peramba_db_pass eramba 2>&1'
    )
    return result


def collect_db_state(runner):
    """Collect current DB counts as evidence."""
    tables = ['risks', 'security_services', 'security_policies', 'third_parties',
              'projects', 'policy_exceptions', 'security_incidents', 'assets']
    state = {}
    for table in tables:
        count = runner.exec_capture(
            f'docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e '
            f'"SELECT COUNT(*) FROM {table};" 2>/dev/null'
        )
        state[f'{table}_count'] = (count or '').strip()
    return state


def test_do_nothing(task_name):
    """Do-nothing test: env.reset() + env.step([], mark_done=True) → score=0, passed=False."""
    print(f"\n{'='*60}")
    print(f"DO-NOTHING RE-TEST: {task_name}")
    print('='*60)

    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "test_type": "do_nothing_retest",
        "env_loaded": False,
        "do_nothing_score": None,
        "do_nothing_passed": None,
        "do_nothing_test_pass": False,
        "errors": [],
    }

    env = None
    try:
        env = from_config(ENV_PATH, task_id=task_name)
        obs = env.reset(seed=42, use_cache=True, use_savevm=True)
        evidence["env_loaded"] = True
        print(f"  Env loaded. VNC: {env._runner.vnc_port}")

        baseline_content = env._runner.exec_capture(
            f'cat /tmp/{task_name}_baseline.txt 2>/dev/null'
        )
        evidence["baseline"] = (baseline_content or '').strip()
        print(f"  Baseline: {evidence['baseline'][:150]}")

        evidence["initial_db_state"] = collect_db_state(env._runner)

        # Screenshot
        screenshot_path = f'/tmp/{task_name}_retest_screenshot.png'
        env._runner.exec_capture(
            f'DISPLAY=:1 scrot {screenshot_path} 2>/dev/null || true'
        )
        time.sleep(1)
        try:
            local_path = f'{EVIDENCE_DIR}/{task_name}_retest_screenshot.png'
            env._runner.copy_from(screenshot_path, local_path)
            evidence["screenshot"] = local_path
        except Exception as e:
            evidence["errors"].append(f"screenshot: {e}")

        # Do-nothing step
        obs, reward, done, info = env.step([], mark_done=True)
        result = info.get("verifier", {})
        score = result.get("score", -1)
        passed = result.get("passed", None)
        feedback = result.get("feedback", "")

        evidence["do_nothing_score"] = score
        evidence["do_nothing_passed"] = passed
        evidence["do_nothing_feedback"] = feedback
        evidence["do_nothing_test_pass"] = (score == 0 and passed is False)

        print(f"  Score={score}, Passed={passed}")
        print(f"  Feedback: {feedback}")

        if evidence["do_nothing_test_pass"]:
            print(f"  ✓ DO-NOTHING PASS (score=0, passed=False)")
        else:
            msg = f"expected score=0/passed=False, got score={score}/passed={passed}"
            print(f"  ✗ DO-NOTHING FAIL: {msg}")
            evidence["errors"].append(msg)

    except Exception as e:
        import traceback
        evidence["errors"].append(f"exception: {e}")
        traceback.print_exc()
    finally:
        if env:
            try:
                env.close()
            except Exception:
                pass

    return evidence


def test_partial(task_name):
    """Partial completion test: inject minimal DB records → score in (0, 60), passed=False."""
    print(f"\n{'='*60}")
    print(f"PARTIAL TEST: {task_name}")
    print('='*60)

    injections = PARTIAL_INJECTIONS.get(task_name, [])
    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "test_type": "partial",
        "injected_sqls": injections,
        "partial_score": None,
        "partial_passed": None,
        "partial_test_pass": False,
        "errors": [],
    }

    if not injections:
        print(f"  No partial injection defined for {task_name}, skipping")
        evidence["errors"].append("no_partial_injection_defined")
        return evidence

    env = None
    try:
        env = from_config(ENV_PATH, task_id=task_name)
        obs = env.reset(seed=42, use_cache=True, use_savevm=True)
        print(f"  Env loaded. VNC: {env._runner.vnc_port}")
        time.sleep(2)

        baseline_content = env._runner.exec_capture(
            f'cat /tmp/{task_name}_baseline.txt 2>/dev/null'
        )
        print(f"  Baseline: {(baseline_content or '').strip()[:150]}")
        evidence["baseline"] = (baseline_content or '').strip()

        # Inject records using temp-file approach to avoid shell quoting issues
        for sql in injections:
            result = mysql_inject(env._runner, sql)
            result_str = (result or '').strip()[:120]
            print(f"  SQL: {sql[:80]}...")
            print(f"  Result: {result_str}")
            if 'error' in result_str.lower() or 'errno' in result_str.lower():
                evidence["errors"].append(f"injection_error: {result_str}")

        print(f"  Injected {len(injections)} records.")
        evidence["post_inject_db_state"] = collect_db_state(env._runner)
        print(f"  Post-inject DB: {evidence['post_inject_db_state']}")

        # Run verifier
        obs, reward, done, info = env.step([], mark_done=True)
        result = info.get("verifier", {})
        score = result.get("score", -1)
        passed = result.get("passed", None)
        feedback = result.get("feedback", "")

        evidence["partial_score"] = score
        evidence["partial_passed"] = passed
        evidence["partial_feedback"] = feedback
        evidence["partial_test_pass"] = (0 < score < 60 and passed is False)

        print(f"  Score={score}, Passed={passed}")
        print(f"  Feedback: {feedback}")

        if evidence["partial_test_pass"]:
            print(f"  ✓ PARTIAL PASS (0 < score={score} < 60, passed=False)")
        else:
            if score == 0:
                msg = f"score=0, injection may have failed"
            elif score >= 60:
                msg = f"score={score} >= 60, too high"
            else:
                msg = f"unexpected: score={score}, passed={passed}"
            print(f"  ✗ PARTIAL RESULT: {msg}")
            evidence["errors"].append(msg)

    except Exception as e:
        import traceback
        evidence["errors"].append(f"exception: {e}")
        traceback.print_exc()
    finally:
        if env:
            try:
                env.close()
            except Exception:
                pass

    return evidence


def main():
    os.makedirs(EVIDENCE_DIR, exist_ok=True)
    os.makedirs('/tmp/qemu_work', exist_ok=True)

    print("=" * 70)
    print("ERAMBA ENV - TARGETED PHASE 4+5 RE-TEST")
    print("=" * 70)

    all_results = {}

    # === Phase 4 re-tests (only for tasks that need it) ===
    print("\n>>> PHASE 4 RE-TESTS: DO-NOTHING (vendor/hipaa/pci) <<<")
    for task_name in RETEST_DO_NOTHING:
        ev = test_do_nothing(task_name)
        all_results[task_name] = {"do_nothing_retest": ev}

        # Update existing evidence file
        existing_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
        try:
            with open(existing_path) as f:
                existing = json.load(f)
        except Exception:
            existing = {}
        existing["do_nothing_retest"] = ev
        existing["do_nothing_score_RETEST"] = ev.get("do_nothing_score")
        existing["do_nothing_test_pass_RETEST"] = ev.get("do_nothing_test_pass")
        with open(existing_path, 'w') as f:
            json.dump(existing, f, indent=2)
        print(f"  Evidence updated: {existing_path}")

    # === Phase 5: Partial completion tests for all 5 tasks ===
    print("\n>>> PHASE 5: PARTIAL COMPLETION TESTS (all 5 tasks) <<<")
    for task_name in ALL_TASKS:
        if task_name not in all_results:
            all_results[task_name] = {}
        ev = test_partial(task_name)
        all_results[task_name]["partial"] = ev

        # Update evidence file
        existing_path = f'{EVIDENCE_DIR}/{task_name}_evidence.json'
        try:
            with open(existing_path) as f:
                existing = json.load(f)
        except Exception:
            existing = {}
        existing["partial_test_v2"] = ev
        with open(existing_path, 'w') as f:
            json.dump(existing, f, indent=2)

    # === Summary ===
    print("\n" + "=" * 70)
    print("TEST SUMMARY")
    print("=" * 70)

    # Do-nothing status (combine confirmed + re-tested)
    confirmed_passing = {
        'ransomware_incident_postmortem': True,  # score=0, confirmed
        'annual_policy_review_cycle': True,       # score=0, confirmed
    }

    all_ok = True
    for task_name in ALL_TASKS:
        dn_ev = all_results.get(task_name, {}).get("do_nothing_retest", {})
        if task_name in RETEST_DO_NOTHING:
            dn_ok = dn_ev.get("do_nothing_test_pass", False)
            dn_score = dn_ev.get("do_nothing_score", "N/A")
        else:
            dn_ok = confirmed_passing.get(task_name, False)
            dn_score = 0  # confirmed

        pt_ev = all_results.get(task_name, {}).get("partial", {})
        pt_ok = pt_ev.get("partial_test_pass", False)
        pt_score = pt_ev.get("partial_score", "N/A")

        dn_mark = "✓" if dn_ok else "✗"
        pt_mark = "✓" if pt_ok else "?"

        print(f"  {dn_mark}/{pt_mark} {task_name}")
        print(f"    do-nothing: score={dn_score}, ok={dn_ok}")
        print(f"    partial:    score={pt_score}, ok={pt_ok}")
        if pt_ev.get("errors"):
            print(f"    errors: {pt_ev['errors']}")

        if not dn_ok:
            all_ok = False

    print(f"\nAll do-nothing tests pass: {all_ok}")
    print("\nResults saved to evidence/")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
