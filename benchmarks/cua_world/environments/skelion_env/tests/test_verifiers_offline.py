#!/usr/bin/env python3
"""
Offline verification tests for all 5 new skelion_env tasks.

Phase 5 validation per task_creation_notes/06_task_creation_checklist.md:
  - Do-nothing test: agent does nothing → score = 0
  - Wrong-target test: agent completes for wrong location → score = 0
  - Partial completion test: agent does partial work → 0 < score < 100

Full completion is NOT tested (we cannot run SketchUp offline).
"""

import json
import os
import sys
import tempfile

# Add the tasks directory so verifier modules can be imported
TASKS_DIR = os.path.join(os.path.dirname(__file__), "..", "tasks")
sys.path.insert(0, TASKS_DIR)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_env_info(result_dict, result_filename):
    """Create a mock env_info with copy_from_env that writes result_dict to /tmp."""
    # Use a distinct path from the verifier's local_tmp to avoid SameFileError
    staging_path = os.path.join(tempfile.gettempdir(), "mock_" + result_filename)
    with open(staging_path, "w", encoding="utf-8") as f:
        json.dump(result_dict, f)

    def copy_from_env(remote_path, local_dest):
        import shutil
        shutil.copy2(staging_path, local_dest)

    return {"copy_from_env": copy_from_env}


def _run_verifier(verify_fn, result_dict, result_filename):
    env_info = _make_env_info(result_dict, result_filename)
    return verify_fn(traj=[], env_info=env_info, task_info={})


# ===========================================================================
# Task 1: pv_layout_from_client_brief
# ===========================================================================

def test_pv_layout_do_nothing():
    from pv_layout_from_client_brief.verifier import verify_pv_layout_from_client_brief
    result = {
        "latitude": 0.0, "longitude": 0.0,
        "panel_delta": 0,
        "csv_exists": False, "csv_size_bytes": 0, "csv_is_new": False,
    }
    out = _run_verifier(verify_pv_layout_from_client_brief, result, "pv_layout_result.json")
    assert out["score"] == 0, f"Do-nothing should score 0, got {out['score']}"
    assert not out["passed"], "Do-nothing should not pass"
    print(f"  [PASS] pv_layout do-nothing: score={out['score']}")


def test_pv_layout_wrong_target():
    from pv_layout_from_client_brief.verifier import verify_pv_layout_from_client_brief
    # Agent sets Tokyo instead of San Francisco
    result = {
        "latitude": 35.6762, "longitude": 139.6503,
        "panel_delta": 80,
        "csv_exists": True, "csv_size_bytes": 500, "csv_is_new": True,
    }
    out = _run_verifier(verify_pv_layout_from_client_brief, result, "pv_layout_result.json")
    # Location wrong (0), panels OK (40), CSV OK (30) = 70 — but location is wrong-target
    # This tests that wrong location doesn't get location points
    assert out["score"] <= 70, f"Wrong location should score <=70, got {out['score']}"
    assert "WRONG" in out["feedback"]
    print(f"  [PASS] pv_layout wrong-target: score={out['score']}")


def test_pv_layout_partial():
    from pv_layout_from_client_brief.verifier import verify_pv_layout_from_client_brief
    # Agent sets correct location, places some panels, no CSV
    result = {
        "latitude": 37.75, "longitude": -122.42,
        "panel_delta": 30,
        "csv_exists": False, "csv_size_bytes": 0, "csv_is_new": False,
    }
    out = _run_verifier(verify_pv_layout_from_client_brief, result, "pv_layout_result.json")
    # Location OK (30), partial panels (30/75 * 40 = 16, capped at 20), no CSV (0)
    assert 0 < out["score"] < 100, f"Partial should be 0 < score < 100, got {out['score']}"
    print(f"  [PASS] pv_layout partial: score={out['score']}")


# ===========================================================================
# Task 2: shadow_study_panel_placement
# ===========================================================================

def test_shadow_study_do_nothing():
    from shadow_study_panel_placement.verifier import verify_shadow_study_panel_placement
    result = {
        "latitude": 0.0, "longitude": 0.0,
        "panel_delta": 0,
        "report_exists": False, "report_size_bytes": 0,
        "report_is_new": False, "report_content": "",
    }
    out = _run_verifier(verify_shadow_study_panel_placement, result, "shadow_study_result.json")
    assert out["score"] == 0, f"Do-nothing should score 0, got {out['score']}"
    assert not out["passed"]
    print(f"  [PASS] shadow_study do-nothing: score={out['score']}")


def test_shadow_study_wrong_target():
    from shadow_study_panel_placement.verifier import verify_shadow_study_panel_placement
    # Agent sets Miami instead of Denver
    result = {
        "latitude": 25.7617, "longitude": -80.1918,
        "panel_delta": 50,
        "report_exists": True, "report_size_bytes": 200,
        "report_is_new": True, "report_content": "Shadow report for Miami, FL. 50 panels placed.",
    }
    out = _run_verifier(verify_shadow_study_panel_placement, result, "shadow_study_result.json")
    # Location wrong (0), panels OK (35), report exists (25) + some bonus = ~60-65
    assert "WRONG" in out["feedback"]
    print(f"  [PASS] shadow_study wrong-target: score={out['score']}")


def test_shadow_study_partial():
    from shadow_study_panel_placement.verifier import verify_shadow_study_panel_placement
    # Denver location correct, few panels, no report
    result = {
        "latitude": 39.59, "longitude": -104.75,
        "panel_delta": 15,
        "report_exists": False, "report_size_bytes": 0,
        "report_is_new": False, "report_content": "",
    }
    out = _run_verifier(verify_shadow_study_panel_placement, result, "shadow_study_result.json")
    # Location OK (30), partial panels (15/40 * 35 = 13, capped at 18), no report (0)
    assert 0 < out["score"] < 100, f"Partial should be 0 < score < 100, got {out['score']}"
    print(f"  [PASS] shadow_study partial: score={out['score']}")


# ===========================================================================
# Task 3: net_zero_system_design
# ===========================================================================

def test_net_zero_do_nothing():
    from net_zero_system_design.verifier import verify_net_zero_system_design
    result = {
        "latitude": 0.0, "longitude": 0.0,
        "panel_delta": 0,
        "report_exists": False, "report_size_bytes": 0,
        "report_is_new": False, "report_content": "",
    }
    out = _run_verifier(verify_net_zero_system_design, result, "net_zero_result.json")
    assert out["score"] == 0, f"Do-nothing should score 0, got {out['score']}"
    assert not out["passed"]
    print(f"  [PASS] net_zero do-nothing: score={out['score']}")


def test_net_zero_wrong_target():
    from net_zero_system_design.verifier import verify_net_zero_system_design
    # Agent sets Chicago instead of Austin
    result = {
        "latitude": 41.8781, "longitude": -87.6298,
        "panel_delta": 70,
        "report_exists": True, "report_size_bytes": 300,
        "report_is_new": True,
        "report_content": "Net zero report for Chicago. 70 panels producing 100,000 kWh/year. Feasible.",
    }
    out = _run_verifier(verify_net_zero_system_design, result, "net_zero_result.json")
    assert "WRONG" in out["feedback"]
    print(f"  [PASS] net_zero wrong-target: score={out['score']}")


def test_net_zero_partial():
    from net_zero_system_design.verifier import verify_net_zero_system_design
    # Correct Austin location, some panels, no report
    result = {
        "latitude": 30.41, "longitude": -97.85,
        "panel_delta": 25,
        "report_exists": False, "report_size_bytes": 0,
        "report_is_new": False, "report_content": "",
    }
    out = _run_verifier(verify_net_zero_system_design, result, "net_zero_result.json")
    assert 0 < out["score"] < 100, f"Partial should be 0 < score < 100, got {out['score']}"
    print(f"  [PASS] net_zero partial: score={out['score']}")


# ===========================================================================
# Task 4: location_error_correction
# ===========================================================================

def test_location_error_do_nothing():
    from location_error_correction.verifier import verify_location_error_correction
    # Agent does nothing — location stays at London (seeded)
    result = {
        "latitude": 51.5074, "longitude": -0.1278,
        "panel_delta": 0,
        "seeded_lat": 51.5074, "seeded_lon": -0.1278,
    }
    out = _run_verifier(verify_location_error_correction, result, "location_correction_result.json")
    assert out["score"] == 0, f"Do-nothing should score 0, got {out['score']}"
    assert not out["passed"]
    assert "NOT CORRECTED" in out["feedback"]
    print(f"  [PASS] location_error do-nothing: score={out['score']}")


def test_location_error_wrong_target():
    from location_error_correction.verifier import verify_location_error_correction
    # Agent changes location but to wrong city (LA instead of Atlanta)
    result = {
        "latitude": 34.0522, "longitude": -118.2437,
        "panel_delta": 60,
        "seeded_lat": 51.5074, "seeded_lon": -0.1278,
    }
    out = _run_verifier(verify_location_error_correction, result, "location_correction_result.json")
    # Changed from London (15), not Atlanta, panels OK (40) = 55 — not passing
    assert out["score"] < 60 or "CHANGED from London but not Atlanta" in out["feedback"]
    print(f"  [PASS] location_error wrong-target: score={out['score']}")


def test_location_error_partial():
    from location_error_correction.verifier import verify_location_error_correction
    # Agent corrects to Atlanta but places no panels
    result = {
        "latitude": 33.749, "longitude": -84.388,
        "panel_delta": 0,
        "seeded_lat": 51.5074, "seeded_lon": -0.1278,
    }
    out = _run_verifier(verify_location_error_correction, result, "location_correction_result.json")
    # Atlanta correct (40), no panels (0), no bonus = 40
    assert 0 < out["score"] < 100, f"Partial should be 0 < score < 100, got {out['score']}"
    assert not out["passed"], f"Score {out['score']} should not pass (need 60)"
    print(f"  [PASS] location_error partial: score={out['score']}")


# ===========================================================================
# Task 5: permit_package_preparation
# ===========================================================================

def test_permit_package_do_nothing():
    from permit_package_preparation.verifier import verify_permit_package_preparation
    result = {
        "latitude": 0.0, "longitude": 0.0,
        "panel_delta": 0,
        "permit_file_exists": False, "permit_file_size": 0,
        "permit_file_is_new": False,
        "working_model_lat": 0.0, "working_model_lon": 0.0,
        "working_panel_delta": 0,
    }
    out = _run_verifier(verify_permit_package_preparation, result, "permit_package_result.json")
    assert out["score"] == 0, f"Do-nothing should score 0, got {out['score']}"
    assert not out["passed"]
    print(f"  [PASS] permit_package do-nothing: score={out['score']}")


def test_permit_package_wrong_target():
    from permit_package_preparation.verifier import verify_permit_package_preparation
    # Agent sets Houston instead of NYC
    result = {
        "latitude": 29.7604, "longitude": -95.3698,
        "panel_delta": 80,
        "permit_file_exists": True, "permit_file_size": 100000,
        "permit_file_is_new": True,
        "working_model_lat": 29.7604, "working_model_lon": -95.3698,
        "working_panel_delta": 80,
    }
    out = _run_verifier(verify_permit_package_preparation, result, "permit_package_result.json")
    assert "WRONG" in out["feedback"]
    print(f"  [PASS] permit_package wrong-target: score={out['score']}")


def test_permit_package_partial():
    from permit_package_preparation.verifier import verify_permit_package_preparation
    # NYC location correct, correct panel count, but no Permit_Ready.skp
    result = {
        "latitude": 40.71, "longitude": -74.01,
        "panel_delta": 80,
        "permit_file_exists": False, "permit_file_size": 0,
        "permit_file_is_new": False,
        "working_model_lat": 40.71, "working_model_lon": -74.01,
        "working_panel_delta": 80,
    }
    out = _run_verifier(verify_permit_package_preparation, result, "permit_package_result.json")
    # Location OK (25), panels OK (35), no permit file (0) = 60
    assert 0 < out["score"] < 100, f"Partial should be 0 < score < 100, got {out['score']}"
    print(f"  [PASS] permit_package partial: score={out['score']}")


def test_permit_package_too_many_panels():
    from permit_package_preparation.verifier import verify_permit_package_preparation
    # NYC correct, but too many panels (>150 violates structural limit)
    result = {
        "latitude": 40.71, "longitude": -74.01,
        "panel_delta": 200,
        "permit_file_exists": True, "permit_file_size": 120000,
        "permit_file_is_new": True,
        "working_model_lat": 40.71, "working_model_lon": -74.01,
        "working_panel_delta": 200,
    }
    out = _run_verifier(verify_permit_package_preparation, result, "permit_package_result.json")
    # Location OK (25), panels over limit (15 partial), permit OK (40) = 80
    assert out["score"] < 100, f"Too many panels should score < 100, got {out['score']}"
    assert "OVER LIMIT" in out["feedback"]
    print(f"  [PASS] permit_package too-many-panels: score={out['score']}")


# ===========================================================================
# Main
# ===========================================================================

if __name__ == "__main__":
    tests = [
        # pv_layout_from_client_brief
        ("pv_layout_from_client_brief", test_pv_layout_do_nothing),
        ("pv_layout_from_client_brief", test_pv_layout_wrong_target),
        ("pv_layout_from_client_brief", test_pv_layout_partial),
        # shadow_study_panel_placement
        ("shadow_study_panel_placement", test_shadow_study_do_nothing),
        ("shadow_study_panel_placement", test_shadow_study_wrong_target),
        ("shadow_study_panel_placement", test_shadow_study_partial),
        # net_zero_system_design
        ("net_zero_system_design", test_net_zero_do_nothing),
        ("net_zero_system_design", test_net_zero_wrong_target),
        ("net_zero_system_design", test_net_zero_partial),
        # location_error_correction
        ("location_error_correction", test_location_error_do_nothing),
        ("location_error_correction", test_location_error_wrong_target),
        ("location_error_correction", test_location_error_partial),
        # permit_package_preparation
        ("permit_package_preparation", test_permit_package_do_nothing),
        ("permit_package_preparation", test_permit_package_wrong_target),
        ("permit_package_preparation", test_permit_package_partial),
        ("permit_package_preparation", test_permit_package_too_many_panels),
    ]

    passed = 0
    failed = 0
    errors = []

    for task_name, test_fn in tests:
        try:
            test_fn()
            passed += 1
        except AssertionError as e:
            failed += 1
            errors.append(f"  FAIL {task_name}/{test_fn.__name__}: {e}")
            print(f"  [FAIL] {task_name}/{test_fn.__name__}: {e}")
        except Exception as e:
            failed += 1
            errors.append(f"  ERROR {task_name}/{test_fn.__name__}: {type(e).__name__}: {e}")
            print(f"  [ERROR] {task_name}/{test_fn.__name__}: {type(e).__name__}: {e}")

    print(f"\n{'='*60}")
    print(f"Results: {passed} passed, {failed} failed out of {len(tests)} tests")
    if errors:
        print("Failures:")
        for e in errors:
            print(e)
    sys.exit(0 if failed == 0 else 1)
