#!/usr/bin/env python3
"""Comprehensive evidence collection and validation tests for virtualmin_env tasks.

This script:
1. Boots the VM with each task → collects evidence + do-nothing test
2. Runs wrong-target tests offline (calls verifier directly with mock data)
3. Runs partial completion tests offline (calls verifier directly with mock data)
"""

import sys
import os
import time
import json
import shutil
import tempfile
import importlib.util

# Ensure we're in the repo root
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
os.chdir(REPO_ROOT)
sys.path.insert(0, REPO_ROOT)

from gym_anything.api import from_config

ENV_DIR = "benchmarks/environments/virtualmin_env"
EVIDENCE_DIR = os.path.join(ENV_DIR, "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

TASKS = [
    "configure_domain_resource_limits",
    "setup_mail_forwarding_chain",
    "migrate_database_across_domains",
    "harden_domain_security",
    "setup_scheduled_backup",
]

# Task metadata (from task.json files)
TASK_METADATA = {
    "configure_domain_resource_limits": {
        "target_domain": "greenvalley.test",
        "expected_quota_mb": 500, "expected_bw_gb": 5,
        "expected_max_mailboxes": 10, "expected_max_aliases": 20, "expected_max_dbs": 3,
    },
    "setup_mail_forwarding_chain": {
        "target_domain": "acmecorp.test",
    },
    "migrate_database_across_domains": {
        "target_domain": "brightstar.test",
    },
    "harden_domain_security": {
        "target_domain": "acmecorp.test",
    },
    "setup_scheduled_backup": {
        "target_domains": ["acmecorp.test", "brightstar.test", "greenvalley.test"],
        "retention_count": 7,
    },
}

# Verifier function names
VERIFIER_FUNCS = {
    "configure_domain_resource_limits": "verify_configure_domain_resource_limits",
    "setup_mail_forwarding_chain": "verify_setup_mail_forwarding_chain",
    "migrate_database_across_domains": "verify_migrate_database_across_domains",
    "harden_domain_security": "verify_harden_domain_security",
    "setup_scheduled_backup": "verify_setup_scheduled_backup",
}

# ─── Wrong-target JSON payloads ────────────────────────────────────────────────
WRONG_TARGET_PAYLOADS = {
    "configure_domain_resource_limits": {
        "domain": "brightstar.test",
        "quota_raw": "512000", "bw_raw": "5368709120",
        "max_mailboxes_raw": "10", "max_aliases_raw": "20", "max_dbs_raw": "3",
        "quota_parsed": 512000, "bw_parsed": 5368709120,
        "max_mailboxes_parsed": 10, "max_aliases_parsed": 20, "max_dbs_parsed": 3,
    },
    "setup_mail_forwarding_chain": {
        "domain": "greenvalley.test",
        "hr_user_exists": True, "billing_user_exists": True,
        "jobs_alias_exists": True, "jobs_alias_dest": "hr@greenvalley.test",
        "invoices_alias_exists": True, "invoices_alias_dest": "billing@greenvalley.test",
        "contact_alias_exists": True, "contact_alias_dest": "info@greenvalley.test admin@greenvalley.test",
        "contact_has_info_dest": True, "contact_has_admin_dest": True,
    },
    "migrate_database_across_domains": {
        "domain": "acmecorp.test",
        "catalog_db_exists": True, "catalog_db_name": "acmecorp_catalog",
        "table_exists": True, "table_columns": "id,name,description,created_at",
        "has_id_column": True, "has_name_column": True,
        "has_description_column": True, "has_created_at_column": True,
        "row_count": 10, "category_names": "Action|Comedy|Drama|Horror|Sci-Fi",
        "sakila_grant": True,
    },
    "harden_domain_security": {
        "domain": "brightstar.test",
        "spf_exists": True, "spf_record": "v=spf1 a mx ~all",
        "dkim_enabled": True, "dkim_dns_record": True,
        "ssl_redirect": True, "nosniff_header": True, "indexes_disabled": True,
    },
    "setup_scheduled_backup": {
        "backup_found": True,
        "has_acmecorp": False,  # WRONG: none of the required domains
        "has_brightstar": False,
        "has_greenvalley": False,
        "has_all_domains": False,
        "dest_is_local": True, "dest_path": "/backup/virtualmin/",
        "schedule_daily": True,
        "has_dir_feature": True, "has_mail_feature": True,
        "has_mysql_feature": True, "has_dns_feature": True,
        "retention_count": 7, "backup_dir_exists": True,
    },
}

# ─── Partial completion JSON payloads ──────────────────────────────────────────
PARTIAL_PAYLOADS = {
    "configure_domain_resource_limits": {
        "domain": "greenvalley.test",
        "quota_raw": "512000", "quota_parsed": 512000,
        "bw_raw": "5368709120", "bw_parsed": 5368709120,
        "max_mailboxes_raw": "UNLIMITED", "max_mailboxes_parsed": None,
        "max_aliases_raw": "UNLIMITED", "max_aliases_parsed": None,
        "max_dbs_raw": "UNLIMITED", "max_dbs_parsed": None,
    },
    "setup_mail_forwarding_chain": {
        "domain": "acmecorp.test",
        "hr_user_exists": True, "billing_user_exists": False,
        "jobs_alias_exists": True, "jobs_alias_dest": "hr@acmecorp.test",
        "invoices_alias_exists": False, "invoices_alias_dest": "",
        "contact_alias_exists": False, "contact_alias_dest": "",
        "contact_has_info_dest": False, "contact_has_admin_dest": False,
    },
    "migrate_database_across_domains": {
        "domain": "brightstar.test",
        "catalog_db_exists": True, "catalog_db_name": "brightstar_catalog",
        "table_exists": False, "table_columns": "",
        "has_id_column": False, "has_name_column": False,
        "has_description_column": False, "has_created_at_column": False,
        "row_count": 0, "category_names": "",
        "sakila_grant": True,
    },
    "harden_domain_security": {
        "domain": "acmecorp.test",
        "spf_exists": True, "spf_record": "v=spf1 a mx ~all",
        "dkim_enabled": True, "dkim_dns_record": True,
        "ssl_redirect": False, "nosniff_header": False, "indexes_disabled": False,
    },
    "setup_scheduled_backup": {
        "backup_found": True,
        "has_acmecorp": True, "has_brightstar": True, "has_greenvalley": True,
        "has_all_domains": True,
        "dest_is_local": True, "dest_path": "/backup/virtualmin/",
        "schedule_daily": False,
        "has_dir_feature": True, "has_mail_feature": True,
        "has_mysql_feature": False, "has_dns_feature": False,
        "retention_count": 0, "backup_dir_exists": True,
    },
}

EXPECTED_PARTIAL_RANGES = {
    "configure_domain_resource_limits": (40, 60),
    "setup_mail_forwarding_chain": (35, 45),
    "migrate_database_across_domains": (35, 45),
    "harden_domain_security": (35, 45),
    "setup_scheduled_backup": (40, 60),
}


def load_verifier_func(task_name):
    """Dynamically load the verifier function for a task."""
    verifier_path = os.path.join(ENV_DIR, "tasks", task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", verifier_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    func_name = VERIFIER_FUNCS[task_name]
    return getattr(module, func_name)


def make_mock_copy_from_env(payload, task_name):
    """Create a mock copy_from_env that serves the given JSON payload."""
    result_path = f"/tmp/{task_name}_result.json"

    def copy_from_env(remote_path, local_path):
        if remote_path == result_path:
            with open(local_path, 'w') as f:
                json.dump(payload, f, indent=2)
        else:
            raise FileNotFoundError(f"Mock: {remote_path} not found")

    return copy_from_env


def call_verifier_offline(task_name, payload):
    """Call a verifier function directly with a mock payload (no VM needed)."""
    verify_func = load_verifier_func(task_name)
    mock_copy = make_mock_copy_from_env(payload, task_name)
    env_info = {"copy_from_env": mock_copy}
    task_info = {"metadata": TASK_METADATA.get(task_name, {})}
    return verify_func([], env_info, task_info)


def collect_evidence(env, task_name):
    """Collect screenshots and evidence JSON for a task."""
    evidence = {
        "task": task_name,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "checks": {},
        "setup_files_created": [],
    }

    print(f"\n  [SETUP] Checking setup files...")
    setup_check = env._runner.exec_capture('ls -la /tmp/initial_* /tmp/task_start_* 2>&1')
    evidence["checks"]["setup_files"] = setup_check.strip()
    print(f"  {setup_check.strip()[:200]}")

    print(f"  [SERVICES] Checking Virtualmin...")
    service_check = env._runner.exec_capture('systemctl is-active webmin 2>&1')
    evidence["checks"]["webmin_status"] = service_check.strip()
    print(f"  Webmin: {service_check.strip()}")

    domains_check = env._runner.exec_capture('virtualmin list-domains --name-only 2>&1')
    evidence["checks"]["domains"] = domains_check.strip()
    print(f"  Domains: {domains_check.strip()}")

    print(f"  [SCREENSHOT] Capturing...")
    screenshot_path = f"{EVIDENCE_DIR}/{task_name}_screenshot.png"
    try:
        env._runner.copy_from('/tmp/task_start_screenshot.png', screenshot_path)
        evidence["screenshot"] = screenshot_path
        print(f"  Screenshot saved: {screenshot_path}")
    except Exception as e:
        print(f"  Screenshot error: {e}")
        try:
            env._runner.exec_capture('DISPLAY=:1 scrot /tmp/evidence_screen.png 2>/dev/null || true')
            time.sleep(0.5)
            env._runner.copy_from('/tmp/evidence_screen.png', screenshot_path)
            evidence["screenshot"] = screenshot_path
            print(f"  Fallback screenshot saved: {screenshot_path}")
        except Exception as e2:
            print(f"  Fallback also failed: {e2}")

    evidence_path = f"{EVIDENCE_DIR}/{task_name}_evidence.json"
    with open(evidence_path, 'w') as f:
        json.dump(evidence, f, indent=2)
    print(f"  Evidence saved: {evidence_path}")
    return evidence


def test_do_nothing_with_vm(env, task_name):
    """Do-nothing test: run export without any agent action, verify score=0."""
    print(f"\n  [DO-NOTHING] Running export script...")
    export_out = env._runner.exec_capture(
        f'bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1'
    )
    if "Export Complete" in export_out:
        print(f"  Export completed successfully")
    else:
        print(f"  Export may have issues: {export_out[-200:]}")

    # Copy the result file and verify offline
    result_path = f"/tmp/{task_name}_result.json"
    local_result = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    local_result.close()
    try:
        env._runner.copy_from(result_path, local_result.name)
        with open(local_result.name) as f:
            payload = json.load(f)
        print(f"  Exported JSON: {json.dumps(payload, indent=2)[:500]}")
    except Exception as e:
        print(f"  Could not read result JSON: {e}")
        payload = {}
    finally:
        os.unlink(local_result.name)

    # Call verifier offline with the exported data
    result = call_verifier_offline(task_name, payload)
    score = result.get('score', -1)
    passed = result.get('passed', True)
    feedback = result.get('feedback', '')

    print(f"  Do-nothing result: score={score}, passed={passed}")
    print(f"  Feedback: {feedback[:300]}")

    if score == 0 and not passed:
        print(f"  [PASS] Do-nothing test passed (score=0, passed=False)")
        return True
    else:
        print(f"  [FAIL] Do-nothing test FAILED (expected score=0/passed=False, got score={score}/passed={passed})")
        return False


def test_wrong_target_offline(task_name):
    """Wrong-target test: call verifier directly with wrong-domain payload."""
    print(f"\n  [WRONG-TARGET] Testing with wrong-target payload (offline)...")
    payload = WRONG_TARGET_PAYLOADS[task_name]

    result = call_verifier_offline(task_name, payload)
    score = result.get('score', -1)
    passed = result.get('passed', True)
    feedback = result.get('feedback', '')

    print(f"  Wrong-target result: score={score}, passed={passed}")
    print(f"  Feedback: {feedback[:300]}")

    if score == 0 and not passed:
        print(f"  [PASS] Wrong-target test passed (score=0, passed=False)")
        return True
    else:
        print(f"  [FAIL] Wrong-target test FAILED (expected score=0/passed=False)")
        return False


def test_partial_offline(task_name):
    """Partial completion test: call verifier directly with partial payload."""
    print(f"\n  [PARTIAL] Testing with partial completion payload (offline)...")
    payload = PARTIAL_PAYLOADS[task_name]
    expected_min, expected_max = EXPECTED_PARTIAL_RANGES[task_name]

    result = call_verifier_offline(task_name, payload)
    score = result.get('score', -1)
    passed = result.get('passed', True)
    feedback = result.get('feedback', '')

    print(f"  Partial result: score={score}, passed={passed}")
    print(f"  Feedback: {feedback[:300]}")
    print(f"  Expected range: {expected_min}-{expected_max}")

    if expected_min <= score <= expected_max and not passed:
        print(f"  [PASS] Partial test passed (score={score} in [{expected_min},{expected_max}], passed=False)")
        return True
    else:
        print(f"  [FAIL] Partial test FAILED (score={score}, expected [{expected_min},{expected_max}], passed={passed})")
        return False


def test_task_vm(task_name, use_cache=True):
    """Boot VM, collect evidence, run do-nothing test."""
    print(f"\n{'='*70}")
    print(f"VM TEST: {task_name}")
    print(f"{'='*70}")

    env = from_config(ENV_DIR, task_id=task_name)
    try:
        print(f"\n  Booting VM (use_cache={use_cache})...")
        obs = env.reset(seed=42, use_cache=use_cache, cache_level="post_start", use_savevm=True)
        print(f"  VM ready - VNC port: {env._runner.vnc_port}")

        print(f"\n--- Evidence Collection ---")
        evidence = collect_evidence(env, task_name)

        print(f"\n--- Do-Nothing Test ---")
        dn_pass = test_do_nothing_with_vm(env, task_name)

        return {"evidence_collected": True, "do_nothing_pass": dn_pass}

    except Exception as e:
        print(f"\n  [ERROR] {task_name} VM test failed: {e}")
        import traceback
        traceback.print_exc()
        return {"evidence_collected": False, "do_nothing_pass": False, "error": str(e)}
    finally:
        try:
            env.close()
        except Exception:
            pass


def main():
    tasks_to_test = TASKS
    skip_vm = False

    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = [a for a in sys.argv[1:] if a.startswith('--')]

    if '--skip-vm' in flags:
        skip_vm = True
        print("Skipping VM tests (--skip-vm flag)")

    if args:
        tasks_to_test = [t for t in args if t in TASKS]
        if not tasks_to_test:
            print(f"Usage: {sys.argv[0]} [--skip-vm] [task_name ...]")
            print(f"Available tasks: {', '.join(TASKS)}")
            sys.exit(1)

    all_results = {}

    # Phase 1: Offline tests (wrong-target + partial) — no VM needed
    print(f"\n{'#'*70}")
    print("PHASE 1: OFFLINE VALIDATION TESTS (no VM)")
    print(f"{'#'*70}")

    for task in tasks_to_test:
        print(f"\n{'='*70}")
        print(f"OFFLINE TESTS: {task}")
        print(f"{'='*70}")

        wt_pass = test_wrong_target_offline(task)
        pc_pass = test_partial_offline(task)

        all_results[task] = {
            "task": task,
            "wrong_target_pass": wt_pass,
            "partial_pass": pc_pass,
        }

    # Phase 2: VM tests (evidence + do-nothing) — requires VM boot
    if not skip_vm:
        print(f"\n{'#'*70}")
        print("PHASE 2: VM TESTS (evidence + do-nothing)")
        print(f"{'#'*70}")

        for task in tasks_to_test:
            vm_result = test_task_vm(task)
            all_results[task].update({
                "evidence_collected": vm_result.get("evidence_collected", False),
                "do_nothing_pass": vm_result.get("do_nothing_pass", False),
            })
            if "error" in vm_result:
                all_results[task]["error"] = vm_result["error"]
    else:
        for task in tasks_to_test:
            all_results[task].update({
                "evidence_collected": False,
                "do_nothing_pass": False,
            })

    # Calculate all_pass
    for task in tasks_to_test:
        r = all_results[task]
        r["all_pass"] = (
            r.get("do_nothing_pass", False) and
            r.get("wrong_target_pass", False) and
            r.get("partial_pass", False)
        )

    # Summary
    print(f"\n{'='*70}")
    print("VALIDATION SUMMARY")
    print(f"{'='*70}")
    for task, result in all_results.items():
        status = "ALL PASS" if result.get("all_pass") else "ISSUES"
        dn = "OK" if result.get("do_nothing_pass") else ("SKIP" if skip_vm else "FAIL")
        wt = "OK" if result.get("wrong_target_pass") else "FAIL"
        pc = "OK" if result.get("partial_pass") else "FAIL"
        ev = "OK" if result.get("evidence_collected") else ("SKIP" if skip_vm else "FAIL")
        print(f"  {task}: [{status}] evidence={ev} do-nothing={dn} wrong-target={wt} partial={pc}")
        if "error" in result:
            print(f"    ERROR: {result['error'][:100]}")

    summary_path = os.path.join(EVIDENCE_DIR, "validation_summary.json")
    with open(summary_path, 'w') as f:
        json.dump(all_results, f, indent=2)
    print(f"\nFull results saved to: {summary_path}")
    print(f"Evidence files in: {EVIDENCE_DIR}/")

    all_pass = all(r.get("all_pass") for r in all_results.values())
    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
