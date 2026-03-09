#!/usr/bin/env python3
"""
Pipeline test script for openlca_env new tasks.

Tests Phase 4 (testing) and Phase 5 (validation) per task_creation_notes/06_task_creation_checklist.md.

Tests per task:
  A) do_nothing_no_export  — copy_from_env raises FileNotFoundError → score=0
  B) do_nothing_baseline   — all-zero JSON → score=0
  C) partial_completion    — DB imported only → 0 < score < 60

Run from repo root:
  python benchmarks/environments/openlca_env/dev/test_new_tasks_pipeline.py

All assertions must pass before the tasks are considered ready.
"""

import json
import os
import sys
import tempfile

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_copy_fn_raises():
    """Returns a copy_from_env function that raises FileNotFoundError."""
    def _copy(src, dst):
        raise FileNotFoundError(f"No such file on environment: {src}")
    return _copy


def make_copy_fn_json(data: dict):
    """Returns a copy_from_env function that writes `data` as JSON to dst."""
    def _copy(src, dst):
        with open(dst, 'w') as f:
            json.dump(data, f)
    return _copy


def run_test(name, verify_fn, task_info, env_info, expect_passed, expect_score_range, label):
    result = verify_fn([], env_info, task_info)
    passed = result.get('passed', None)
    score = result.get('score', -1)
    feedback = result.get('feedback', '')

    ok_passed = (passed == expect_passed)
    ok_score = (expect_score_range[0] <= score <= expect_score_range[1])

    status = "PASS" if (ok_passed and ok_score) else "FAIL"
    print(f"  [{status}] {label}: passed={passed}, score={score}")
    if not (ok_passed and ok_score):
        print(f"         EXPECTED: passed={expect_passed}, score in {expect_score_range}")
        print(f"         FEEDBACK: {feedback[:200]}")
    return ok_passed and ok_score


# ---------------------------------------------------------------------------
# Import verifiers
# ---------------------------------------------------------------------------

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TASK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/tasks"

# Import verifier functions by loading the module files directly
import importlib.util

def load_verifier(task_name):
    spec = importlib.util.spec_from_file_location(
        f"verifier_{task_name}",
        os.path.join(TASK_DIR, task_name, "verifier.py")
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# Baseline (do-nothing) JSON fixtures — derived from verifier result.get() calls
# ---------------------------------------------------------------------------

BASELINE_comparative_packaging_lca = {
    "task": "comparative_packaging_lca",
    "db_found": False,
    "db_size_mb": 0,
    "ps_count": 0,
    "impact_cat_count": 0,
    "initial_result_count": 0,
    "current_result_count": 0,
    "comparison_file": "",
    "comparison_file_size": 0,
    "has_glass_keyword": 0,
    "has_aluminum_keyword": 0,
    "has_gwp_keyword": 0,
    "comparison_row_count": 0,
    "task_start": 1700000000,
    "openlca_running": False,
    "lcia_results_visible": False,
}

PARTIAL_comparative_packaging_lca = {
    **BASELINE_comparative_packaging_lca,
    # DB imported but nothing else
    "db_found": True,
    "db_size_mb": 250,
    "impact_cat_count": 45,
}
# Expected partial score: 15 (db) + 15 (lcia) = 30 < 60 ✓

BASELINE_monte_carlo_uncertainty = {
    "task": "monte_carlo_uncertainty",
    "db_found": False,
    "db_size_mb": 0,
    "ps_count": 0,
    "impact_cat_count": 0,
    "param_count": 0,
    "initial_result_count": 0,
    "current_result_count": 0,
    "mc_file": "",
    "mc_file_size": 0,
    "has_mean_keyword": 0,
    "has_std_keyword": 0,
    "has_confidence_keyword": 0,
    "has_gwp_keyword": 0,
    "mc_data_rows": 0,
    "mc_window_visible": False,
    "mc_in_log": False,
    "task_start": 1700000000,
    "openlca_running": False,
}

PARTIAL_monte_carlo_uncertainty = {
    **BASELINE_monte_carlo_uncertainty,
    # DB and LCIA imported but no PS, no params, no file
    "db_found": True,
    "db_size_mb": 250,
    "impact_cat_count": 45,
}
# Expected partial score: 15 (db) + 10 (lcia) = 25 < 60, gate caps at 30 ✓

BASELINE_supply_chain_hotspot = {
    "task": "supply_chain_hotspot",
    "db_found": False,
    "db_size_mb": 0,
    "ps_count": 0,
    "impact_cat_count": 0,
    "initial_result_count": 0,
    "current_result_count": 0,
    "hotspot_file": "",
    "hotspot_file_size": 0,
    "has_cement_keyword": 0,
    "has_percent_keyword": 0,
    "has_process_keyword": 0,
    "has_gwp_keyword": 0,
    "hotspot_row_count": 0,
    "task_start": 1700000000,
    "openlca_running": False,
    "contribution_visible": False,
}

PARTIAL_supply_chain_hotspot = {
    **BASELINE_supply_chain_hotspot,
    "db_found": True,
    "db_size_mb": 250,
    "impact_cat_count": 45,
}
# Expected partial score: 15 (db) + 10 (lcia) = 25 < 60 ✓

BASELINE_scenario_electricity_comparison = {
    "task": "scenario_electricity_comparison",
    "db_found": False,
    "db_size_mb": 0,
    "ps_count": 0,
    "impact_cat_count": 0,
    "initial_result_count": 0,
    "current_result_count": 0,
    "scenario_file": "",
    "scenario_file_size": 0,
    "has_coal_keyword": 0,
    "has_gas_keyword": 0,
    "has_gwp_keyword": 0,
    "has_acidification_keyword": 0,
    "has_percent_keyword": 0,
    "scenario_row_count": 0,
    "task_start": 1700000000,
    "openlca_running": False,
    "results_visible": False,
}

PARTIAL_scenario_electricity_comparison = {
    **BASELINE_scenario_electricity_comparison,
    "db_found": True,
    "db_size_mb": 250,
    "impact_cat_count": 45,
    "ps_count": 1,
}
# Expected partial score: 15 (db) + 10 (lcia) + 10 (1 PS partial) = 35 < 60 ✓

BASELINE_epd_multi_impact_normalization = {
    "task": "epd_multi_impact_normalization",
    "db_found": False,
    "db_size_mb": 0,
    "ps_count": 0,
    "impact_cat_count": 0,
    "initial_result_count": 0,
    "current_result_count": 0,
    "epd_file": "",
    "epd_file_size": 0,
    "has_gwp_keyword": 0,
    "has_acidification_keyword": 0,
    "has_eutrophication_keyword": 0,
    "has_ozone_keyword": 0,
    "has_additional_category": 0,
    "has_transport_or_ag": 0,
    "category_count": 0,
    "epd_row_count": 0,
    "task_start": 1700000000,
    "openlca_running": False,
    "multi_impact_visible": False,
}

PARTIAL_epd_multi_impact_normalization = {
    **BASELINE_epd_multi_impact_normalization,
    "db_found": True,
    "db_size_mb": 250,
    "impact_cat_count": 45,  # >= 5 → 15 pts for lcia
}
# Expected partial score: 15 (db) + 15 (lcia cats >= 5) = 30 < 60, gate won't fire (category_count=0 < 3) ✓
# Gate caps at 55 — partial score 30 < 55, no cap needed

TASK_INFO_EMPTY = {"metadata": {}}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_task(task_name, baseline_json, partial_json):
    print(f"\n{'='*60}")
    print(f"TASK: {task_name}")
    print('='*60)

    try:
        mod = load_verifier(task_name)
        fn_name = f"verify_{task_name}"
        verify_fn = getattr(mod, fn_name)
    except Exception as e:
        print(f"  [FAIL] Could not load verifier: {e}")
        return False

    all_pass = True

    # ── Test A: do-nothing / no export (FileNotFoundError path) ────────────
    env_a = {"copy_from_env": make_copy_fn_raises()}
    all_pass &= run_test(
        task_name, verify_fn, TASK_INFO_EMPTY, env_a,
        expect_passed=False, expect_score_range=(0, 0),
        label="A: do_nothing_no_export (FileNotFoundError)"
    )

    # ── Test B: do-nothing / baseline JSON (all zeros) ─────────────────────
    env_b = {"copy_from_env": make_copy_fn_json(baseline_json)}
    all_pass &= run_test(
        task_name, verify_fn, TASK_INFO_EMPTY, env_b,
        expect_passed=False, expect_score_range=(0, 0),
        label="B: do_nothing_baseline (all-zero JSON)"
    )

    # ── Test C: partial completion ─────────────────────────────────────────
    env_c = {"copy_from_env": make_copy_fn_json(partial_json)}
    all_pass &= run_test(
        task_name, verify_fn, TASK_INFO_EMPTY, env_c,
        expect_passed=False, expect_score_range=(1, 59),
        label="C: partial_completion (DB imported, nothing else)"
    )

    return all_pass


if __name__ == "__main__":
    tasks = [
        ("comparative_packaging_lca",
         BASELINE_comparative_packaging_lca,
         PARTIAL_comparative_packaging_lca),
        ("monte_carlo_uncertainty",
         BASELINE_monte_carlo_uncertainty,
         PARTIAL_monte_carlo_uncertainty),
        ("supply_chain_hotspot",
         BASELINE_supply_chain_hotspot,
         PARTIAL_supply_chain_hotspot),
        ("scenario_electricity_comparison",
         BASELINE_scenario_electricity_comparison,
         PARTIAL_scenario_electricity_comparison),
        ("epd_multi_impact_normalization",
         BASELINE_epd_multi_impact_normalization,
         PARTIAL_epd_multi_impact_normalization),
    ]

    results = {}
    for name, baseline, partial in tasks:
        results[name] = test_task(name, baseline, partial)

    print(f"\n{'='*60}")
    print("SUMMARY")
    print('='*60)
    all_ok = True
    for name, passed in results.items():
        status = "PASS" if passed else "FAIL"
        print(f"  [{status}] {name}")
        all_ok &= passed

    if all_ok:
        print("\n✓ All pipeline tests passed.")
        sys.exit(0)
    else:
        print("\n✗ Some tests FAILED — fix verifiers before deploying.")
        sys.exit(1)
