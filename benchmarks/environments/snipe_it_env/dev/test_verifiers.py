#!/usr/bin/env python3
"""Phase 5 validation tests for all 5 Snipe-IT very_hard tasks.

Tests:
  1. Do-nothing: export runs with no agent actions -> score=0
  2. Wrong-target: agent modifies the wrong entity -> score=0 or capped
  3. Partial completion: agent completes some but not all subtasks -> partial score
"""

import json
import os
import shutil
import sys
import tempfile
import importlib.util

TASKS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tasks")


def load_verifier(task_name, func_name):
    """Load a verifier function from a task directory, avoiding module name collisions."""
    path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, func_name)


verify_warranty = load_verifier("warranty_audit_remediation", "verify_warranty_audit_remediation")
verify_office = load_verifier("office_closure_asset_transfer", "verify_office_closure_asset_transfer")
verify_license = load_verifier("license_compliance_reconciliation", "verify_license_compliance_reconciliation")
verify_stolen = load_verifier("stolen_device_incident_response", "verify_stolen_device_incident_response")
verify_site = load_verifier("new_site_provisioning", "verify_new_site_provisioning")


def make_mock_env_info(result_json, result_path):
    """Create a mock env_info with a copy_from_env that serves a local JSON file."""
    tmp_dir = tempfile.mkdtemp()
    src_file = os.path.join(tmp_dir, os.path.basename(result_path))
    with open(src_file, 'w') as f:
        json.dump(result_json, f)

    def mock_copy_from_env(vm_path, local_path):
        if vm_path == result_path:
            shutil.copy2(src_file, local_path)
        else:
            raise FileNotFoundError(f"Mock: {vm_path} not found")

    return {"copy_from_env": mock_copy_from_env}, tmp_dir


def run_test(name, verify_fn, result_json, result_path, task_info, expected_score_range, expected_passed):
    """Run a single verification test and check results."""
    env_info, tmp_dir = make_mock_env_info(result_json, result_path)
    try:
        result = verify_fn([], env_info, task_info)
        score = result.get("score", -1)
        passed = result.get("passed", None)
        feedback = result.get("feedback", "")

        in_range = expected_score_range[0] <= score <= expected_score_range[1]
        pass_ok = passed == expected_passed

        status = "PASS" if (in_range and pass_ok) else "FAIL"
        print(f"  [{status}] {name}: score={score} (expected {expected_score_range}), passed={passed} (expected {expected_passed})")
        if status == "FAIL":
            print(f"         Feedback: {feedback[:300]}")
        return status == "PASS"
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_warranty_audit():
    print("\n=== warranty_audit_remediation ===")
    task_info = {"metadata": {}}
    result_path = "/tmp/warranty_audit_remediation_result.json"
    results = []

    # Do-nothing: all assets unchanged
    do_nothing = {
        "injected_assets": {
            "W001": {"found": True, "status_name": "Ready to Deploy", "notes": ""},
            "W002": {"found": True, "status_name": "Deployed", "notes": ""},
            "W003": {"found": True, "status_name": "Ready to Deploy", "notes": ""},
            "W004": {"found": True, "status_name": "Deployed", "notes": ""},
            "W005": {"found": True, "status_name": "Ready to Deploy", "notes": ""}
        },
        "false_positive_count": 0,
        "retired_current_status": "Retired",
        "correctly_pending_count": 0,
        "initial_pending_count": 0
    }
    results.append(run_test("Do-nothing", verify_warranty, do_nothing, result_path, task_info, (0, 0), False))

    # Wrong-target: W004 (active warranty) wrongly changed, expired ones unchanged
    wrong_target = {
        "injected_assets": {
            "W001": {"found": True, "status_name": "Ready to Deploy", "notes": ""},
            "W002": {"found": True, "status_name": "Ready to Deploy", "notes": ""},
            "W003": {"found": True, "status_name": "Ready to Deploy", "notes": ""},
            "W004": {"found": True, "status_name": "Pending", "notes": "WARRANTY EXPIRED"},
            "W005": {"found": True, "status_name": "Ready to Deploy", "notes": ""}
        },
        "false_positive_count": 1,
        "retired_current_status": "Retired",
        "correctly_pending_count": 0,
        "initial_pending_count": 0
    }
    results.append(run_test("Wrong-target", verify_warranty, wrong_target, result_path, task_info, (0, 0), False))

    # Partial: 2 of 4 expired assets fixed
    partial = {
        "injected_assets": {
            "W001": {"found": True, "status_name": "Pending", "notes": "WARRANTY EXPIRED - needs review"},
            "W002": {"found": True, "status_name": "Pending", "notes": "WARRANTY EXPIRED - needs review"},
            "W003": {"found": True, "status_name": "Ready to Deploy", "notes": ""},
            "W004": {"found": True, "status_name": "Deployed", "notes": ""},
            "W005": {"found": True, "status_name": "Ready to Deploy", "notes": ""}
        },
        "false_positive_count": 0,
        "retired_current_status": "Retired",
        "correctly_pending_count": 2,
        "initial_pending_count": 0
    }
    results.append(run_test("Partial", verify_warranty, partial, result_path, task_info, (50, 80), True))

    return all(results)


def test_office_closure():
    print("\n=== office_closure_asset_transfer ===")
    task_info = {"metadata": {}}
    result_path = "/tmp/office_closure_asset_transfer_result.json"
    results = []

    # Do-nothing: London assets still at London
    do_nothing = {
        "initial_london_count": 2,
        "remaining_london_count": 2,
        "relocated_assets": [
            {"tag": "ASSET-D010", "found": True, "location": "London Office", "is_checked_in": False},
            {"tag": "ASSET-M010", "found": True, "location": "London Office", "is_checked_in": True}
        ],
        "initial_london_checked_out": "",
        "relocation_note_count": 0,
        "new_asset_d004": {"found": False},
        "new_asset_m004": {"found": False},
        "non_london_assets_changed": 0
    }
    results.append(run_test("Do-nothing", verify_office, do_nothing, result_path, task_info, (0, 0), False))

    # Partial: assets relocated but no new assets created, no notes
    partial = {
        "initial_london_count": 2,
        "remaining_london_count": 0,
        "relocated_assets": [
            {"tag": "ASSET-D010", "found": True, "location": "New York Office", "is_checked_in": True},
            {"tag": "ASSET-M010", "found": True, "location": "New York Office", "is_checked_in": True}
        ],
        "initial_london_checked_out": "",
        "relocation_note_count": 0,
        "new_asset_d004": {"found": False},
        "new_asset_m004": {"found": False},
        "non_london_assets_changed": 0
    }
    results.append(run_test("Partial", verify_office, partial, result_path, task_info, (50, 70), True))

    return all(results)


def test_license_compliance():
    print("\n=== license_compliance_reconciliation ===")
    task_info = {"metadata": {}}
    result_path = "/tmp/license_compliance_reconciliation_result.json"
    results = []

    # Do-nothing
    do_nothing = {
        "ms365": {"initial_seats": 50, "current_seats": 50, "current_cost": 13200},
        "adobe_cc": {"initial_seats": 10, "current_seats": 10, "current_cost": 6598.80},
        "win11": {"initial_expiry": "2026-06-01", "current_expiry": "2026-06-01", "current_order": "PO-2024-0550"},
        "slack": {"found": False},
        "initial_total_licenses": 3,
        "current_total_licenses": 3
    }
    results.append(run_test("Do-nothing", verify_license, do_nothing, result_path, task_info, (0, 0), False))

    # Partial: only MS365 updated
    partial = {
        "ms365": {"initial_seats": 50, "current_seats": 35, "current_cost": 9240.00},
        "adobe_cc": {"initial_seats": 10, "current_seats": 10, "current_cost": 6598.80},
        "win11": {"initial_expiry": "2026-06-01", "current_expiry": "2026-06-01", "current_order": "PO-2024-0550"},
        "slack": {"found": False},
        "initial_total_licenses": 3,
        "current_total_licenses": 3
    }
    results.append(run_test("Partial", verify_license, partial, result_path, task_info, (20, 40), False))

    return all(results)


def test_stolen_device():
    print("\n=== stolen_device_incident_response ===")
    task_info = {"metadata": {}}
    result_path = "/tmp/stolen_device_incident_response_result.json"
    results = []

    # Do-nothing
    do_nothing = {
        "stolen_asset": {
            "tag": "ASSET-L007",
            "checked_in": False,
            "is_lost_stolen": False,
            "status_name": "Deployed",
            "has_incident_note": False,
            "notes": ""
        },
        "replacement_asset": {
            "tag": "ASSET-L009",
            "checked_out_to_dkim": False,
            "checkout_note": "",
            "note_has_incident": False
        },
        "insurance_asset": {
            "found": False
        },
        "control_asset_unchanged": True,
        "dkim_user_id": 6
    }
    results.append(run_test("Do-nothing", verify_stolen, do_nothing, result_path, task_info, (0, 0), False))

    # Wrong-target: control asset changed
    wrong_target = {
        "stolen_asset": {
            "tag": "ASSET-L007",
            "checked_in": True,
            "is_lost_stolen": True,
            "status_name": "Lost/Stolen",
            "has_incident_note": True,
            "notes": "SI-2025-0042 stolen"
        },
        "replacement_asset": {
            "tag": "ASSET-L009",
            "checked_out_to_dkim": True,
            "checkout_note": "SI-2025-0042 replacement",
            "note_has_incident": True
        },
        "insurance_asset": {
            "found": True,
            "serial": "INSURANCE-CLAIM-SI-2025-0042",
            "status": "Pending"
        },
        "control_asset_unchanged": False,
        "dkim_user_id": 6
    }
    results.append(run_test("Wrong-target (control modified)", verify_stolen, wrong_target, result_path, task_info, (0, 40), False))

    # Partial: only check-in and status change done
    partial = {
        "stolen_asset": {
            "tag": "ASSET-L007",
            "checked_in": True,
            "is_lost_stolen": True,
            "status_name": "Lost/Stolen",
            "has_incident_note": False,
            "notes": ""
        },
        "replacement_asset": {
            "tag": "ASSET-L009",
            "checked_out_to_dkim": False,
            "checkout_note": "",
            "note_has_incident": False
        },
        "insurance_asset": {
            "found": False
        },
        "control_asset_unchanged": True,
        "dkim_user_id": 6
    }
    results.append(run_test("Partial", verify_stolen, partial, result_path, task_info, (30, 40), False))

    return all(results)


def test_new_site():
    print("\n=== new_site_provisioning ===")
    task_info = {"metadata": {}}
    result_path = "/tmp/new_site_provisioning_result.json"
    results = []

    # Do-nothing
    do_nothing = {
        "location": {"found": False},
        "department": {"found": False},
        "user": {"found": False},
        "asset_transfers": {"d001_at_chicago": False, "d002_at_chicago": False, "d001_has_note": False, "d002_has_note": False},
        "monitor_checkout": {"checked_out_to_trivera": False, "checkout_note_correct": False},
        "control_assets_changed": 0
    }
    results.append(run_test("Do-nothing", verify_site, do_nothing, result_path, task_info, (0, 0), False))

    # Partial: only location created
    partial = {
        "location": {"found": True, "city": "Chicago", "state": "IL"},
        "department": {"found": False},
        "user": {"found": False},
        "asset_transfers": {"d001_at_chicago": False, "d002_at_chicago": False, "d001_has_note": False, "d002_has_note": False},
        "monitor_checkout": {"checked_out_to_trivera": False, "checkout_note_correct": False},
        "control_assets_changed": 0
    }
    results.append(run_test("Partial", verify_site, partial, result_path, task_info, (15, 30), False))

    return all(results)


if __name__ == "__main__":
    print("=" * 60)
    print("PHASE 5: VERIFIER VALIDATION TESTS")
    print("=" * 60)

    all_passed = True
    all_passed &= test_warranty_audit()
    all_passed &= test_office_closure()
    all_passed &= test_license_compliance()
    all_passed &= test_stolen_device()
    all_passed &= test_new_site()

    print("\n" + "=" * 60)
    if all_passed:
        print("ALL TESTS PASSED")
    else:
        print("SOME TESTS FAILED")
    print("=" * 60)

    sys.exit(0 if all_passed else 1)
