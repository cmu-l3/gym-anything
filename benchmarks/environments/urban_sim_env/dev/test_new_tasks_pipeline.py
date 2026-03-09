#!/usr/bin/env python3
"""
Pipeline validation tests for the 5 new urban_sim_env very_hard tasks.

Tests two do-nothing scenarios per verifier (Lesson 24):
  Scenario A: copy_from_env raises FileNotFoundError (export never ran)
  Scenario B: export ran but agent did nothing (all-False/zero baseline JSON)

Run from the repo root:
  python benchmarks/environments/urban_sim_env/dev/test_new_tasks_pipeline.py
"""

import sys
import os
import json
import importlib.util
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')

TASKS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'tasks')

# ─── Helper ──────────────────────────────────────────────────────────────────

def load_verifier(task_name):
    """Import verifier.py from a task directory and return the module."""
    verifier_path = os.path.join(TASKS_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_env_info_raise():
    """env_info that raises FileNotFoundError on copy_from_env (Scenario A)."""
    def _raise(src, dst):
        raise FileNotFoundError(f"No such file on environment: {src}")
    return {"copy_from_env": _raise}


def make_env_info_json(data: dict):
    """env_info that writes a mock JSON result to dst (Scenario B)."""
    def _write(src, dst):
        with open(dst, 'w') as f:
            json.dump(data, f)
    return {"copy_from_env": _write}


def load_task_info(task_name):
    """Load task.json metadata for a task."""
    task_json = os.path.join(TASKS_DIR, task_name, 'task.json')
    with open(task_json) as f:
        t = json.load(f)
    return t


def run_test(task_name, fn_name, baseline_json, expected_max_score=0):
    """Run both do-nothing scenarios and assert score == 0, passed == False."""
    mod = load_verifier(task_name)
    fn = getattr(mod, fn_name)
    task_info = load_task_info(task_name)

    failures = []

    # Scenario A: export never ran
    result_a = fn([], make_env_info_raise(), task_info)
    if result_a.get("passed") is not False or result_a.get("score", 999) > expected_max_score:
        failures.append(
            f"  Scenario A FAILED: passed={result_a.get('passed')}, "
            f"score={result_a.get('score')}, feedback={result_a.get('feedback')}"
        )

    # Scenario B: export ran, agent did nothing
    result_b = fn([], make_env_info_json(baseline_json), task_info)
    if result_b.get("passed") is not False or result_b.get("score", 999) > expected_max_score:
        failures.append(
            f"  Scenario B FAILED: passed={result_b.get('passed')}, "
            f"score={result_b.get('score')}, feedback={result_b.get('feedback')}"
        )

    status = "PASS" if not failures else "FAIL"
    print(f"[{status}] {task_name}")
    if failures:
        for f in failures:
            print(f)
    else:
        print(f"  A: score={result_a['score']}, feedback={result_a.get('feedback','')[:80]}")
        print(f"  B: score={result_b['score']}, feedback={result_b.get('feedback','')[:80]}")
    return not bool(failures)


# ─── Baseline JSONs (what export produces when agent does nothing) ─────────────

DISPLACEMENT_RISK_BASELINE = {
    "task_start": 1700000000,
    "csv_exists": False,
    "csv_is_new": False,
    "csv_row_count": 0,
    "csv_columns": [],
    "has_zone_id": False,
    "has_dri_score": False,
    "has_vulnerability_score": False,
    "has_precarity_score": False,
    "has_pressure_score": False,
    "has_low_income_households": False,
    "has_mean_price_per_sqft": False,
    "dri_score_min": None,
    "dri_score_max": None,
    "dri_score_std": None,
    "unique_zone_ids": 0,
    "all_dri_in_0_1": False,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0,
    "gt": {}
}

BUILDING_SEGMENTATION_BASELINE = {
    "task_start": 1700000000,
    "clusters_csv_exists": False,
    "clusters_csv_is_new": False,
    "clusters_csv_row_count": 0,
    "has_building_id": False,
    "has_cluster_id": False,
    "has_price_per_sqft": False,
    "unique_cluster_ids": [],
    "n_unique_clusters": 0,
    "profiles_csv_exists": False,
    "profiles_csv_is_new": False,
    "profiles_csv_row_count": 0,
    "has_profile_cluster_id": False,
    "has_mean_price": False,
    "has_building_count": False,
    "price_ratio": 0,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0,
    "gt": {}
}

DATA_QUALITY_BASELINE = {
    "task_start": 1700000000,
    "report_csv_exists": False,
    "report_csv_is_new": False,
    "report_csv_row_count": 0,
    "has_issue_type": False,
    "has_records_affected": False,
    "has_repair_method": False,
    "has_records_repaired": False,
    "found_physical_issue": False,
    "found_year_issue": False,
    "found_price_issue": False,
    "found_density_issue": False,
    "repaired_csv_exists": False,
    "repaired_csv_is_new": False,
    "repaired_csv_line_count": 0,
    "original_csv_line_count": 0,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0,
    "gt": {}
}

HOUSING_SHORTAGE_BASELINE = {
    "task_start": 1700000000,
    "csv_exists": False,
    "csv_is_new": False,
    "csv_row_count": 0,
    "csv_columns": [],
    "has_year_col": False,
    "has_households_col": False,
    "has_new_units_col": False,
    "has_deficit_col": False,
    "year_values": [],
    "deficit_values": [],
    "new_units_values": [],
    "deficits_vary": False,
    "all_deficits_plausible": False,
    "notebook_has_import_orca": False,
    "notebook_has_orca_run": False,
    "notebook_has_orca_step": False,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0,
    "gt": {}
}

ZONE_EQUITY_BASELINE = {
    "task_start": 1700000000,
    "csv_exists": False,
    "csv_is_new": False,
    "unique_zones": 0,
    "has_zone_id": False,
    "has_total_jobs": False,
    "has_total_households": False,
    "has_equity_gap_score": False,
    "has_low_income_share": False,
    "has_jobs_per_household": False,
    "equity_score_min": None,
    "equity_score_max": None,
    "equity_score_std": None,
    "all_scores_in_0_1": False,
    "scores_vary": False,
    "low_income_share_in_range": False,
    "jobs_per_hh_nonnegative": False,
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0,
    "gt": {}
}


# ─── Tests ────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Do-Nothing Pipeline Tests — urban_sim_env new tasks")
    print("=" * 60)

    results = [
        run_test(
            "displacement_risk_analysis",
            "verify_displacement_risk",
            DISPLACEMENT_RISK_BASELINE,
        ),
        run_test(
            "building_market_segmentation",
            "verify_building_segmentation",
            BUILDING_SEGMENTATION_BASELINE,
        ),
        run_test(
            "data_quality_audit_and_repair",
            "verify_data_quality",
            DATA_QUALITY_BASELINE,
        ),
        run_test(
            "housing_shortage_projection",
            "verify_housing_shortage",
            HOUSING_SHORTAGE_BASELINE,
        ),
        run_test(
            "zone_job_accessibility_equity",
            "verify_zone_job_equity",
            ZONE_EQUITY_BASELINE,
        ),
    ]

    print("=" * 60)
    passed = sum(results)
    total = len(results)
    print(f"Results: {passed}/{total} passed")
    if passed < total:
        print("SOME TESTS FAILED — verifiers may award points in do-nothing state")
        sys.exit(1)
    else:
        print("ALL TESTS PASSED — verifiers correctly return score=0 for do-nothing")


if __name__ == "__main__":
    main()
