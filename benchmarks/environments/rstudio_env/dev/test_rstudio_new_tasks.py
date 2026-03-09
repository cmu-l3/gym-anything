#!/usr/bin/env python3
"""
Pipeline test script for new rstudio_env tasks.

Tests three scenarios per task (per 06_task_creation_checklist.md Phase 4-5):
  Scenario A: export script never ran → copy_from_env raises FileNotFoundError → score=0
  Scenario B: export ran, agent did nothing → baseline JSON (all False/zero) → score=0
  Scenario C: partial completion → single deliverable injected → score is partial (>0, <60)

Usage:
    # Static tests only (no VM needed):
    python3 test_rstudio_new_tasks.py --static

    # Full live test (requires environment running):
    python3 test_rstudio_new_tasks.py --live

The static tests (A and B) run without booting the VM and validate verifier logic.
The live test (C) requires from_config() and actually boots the environment.
"""

import sys
import os
import json
import tempfile
import argparse

# Add repo root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/../..')

# --------------------------------------------------------------------------
# Import verifiers
# --------------------------------------------------------------------------
from examples.rstudio_env.tasks.longitudinal_seizure_gee.verifier import verify_longitudinal_seizure_gee
from examples.rstudio_env.tasks.garch_financial_risk.verifier import verify_garch_financial_risk
from examples.rstudio_env.tasks.cox_survival_cancer.verifier import verify_cox_survival_cancer
from examples.rstudio_env.tasks.noaa_climate_forecast.verifier import verify_noaa_climate_forecast
from examples.rstudio_env.tasks.spatial_kriging_soil.verifier import verify_spatial_kriging_soil

PASS_THRESHOLD = 60

# --------------------------------------------------------------------------
# Helper: make a copy_from_env that always raises FileNotFoundError (Scenario A)
# --------------------------------------------------------------------------
def _copy_raises(src, dst):
    raise FileNotFoundError(f"No such file on environment: {src}")


# --------------------------------------------------------------------------
# Helper: make a copy_from_env that writes a fixed JSON dict (Scenario B)
# --------------------------------------------------------------------------
def _copy_json(data: dict):
    def _impl(src, dst):
        with open(dst, 'w') as f:
            json.dump(data, f)
    return _impl


# --------------------------------------------------------------------------
# Baseline JSONs — represent do-nothing state after setup_task.sh runs
# Field names derived from verifier source (grep for result.get())
# --------------------------------------------------------------------------

BASELINE_SEIZURE_GEE = {
    "task_start": 1700000000,
    "model_csv_exists": False,
    "model_csv_is_new": False,
    "model_csv_has_rr_col": False,
    "model_csv_has_pvalue_col": False,
    "model_csv_rr_in_range": False,
    "diag_csv_exists": False,
    "diag_csv_is_new": False,
    "diag_csv_has_od_metric": False,
    "diag_csv_od_greater_1": False,
    "figure_exists": False,
    "figure_is_new": False,
    "figure_size_bytes": 0,
    "script_is_new": False,
    "script_has_gee_call": False,
    "script_has_output_call": False,
}

BASELINE_GARCH = {
    "task_start": 1700000000,
    "var_csv_exists": False,
    "var_csv_is_new": False,
    "var_csv_has_var95_col": False,
    "var_csv_has_var99_col": False,
    "var_csv_ordering_valid": False,
    "var_csv_vol_in_range": False,
    "var_csv_rows": 0,
    "backtest_csv_exists": False,
    "backtest_csv_is_new": False,
    "backtest_csv_has_kupiec": False,
    "figure_exists": False,
    "figure_is_new": False,
    "figure_size_bytes": 0,
    "figure_is_png": False,
    "script_is_new": False,
    "script_has_garch_fit": False,
    "script_has_rugarch": False,
}

BASELINE_COX = {
    "task_start": 1700000000,
    "cox_csv": {"exists": False, "is_new": False, "has_hr_column": False,
                "has_pvalue_column": False, "horthy_hr_valid": "false", "row_count": 0},
    "ph_test_csv": {"exists": False, "is_new": False, "has_chisq_column": False, "row_count": 0},
    "km_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "forest_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "script": {"exists": False, "modified": False, "has_coxph": False, "has_cox_zph": False},
}

BASELINE_CLIMATE = {
    "task_start": 1700000000,
    "stl_csv": {"exists": False, "is_new": False, "has_trend_column": False,
                "trend_is_positive": False, "row_count": 0},
    "forecast_csv": {"exists": False, "is_new": False, "has_required_columns": False,
                     "forecast_values_valid": False, "row_count": 0},
    "breakpoints_csv": {"exists": False, "is_new": False, "has_required_columns": False, "row_count": 0},
    "plot_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "script": {"modified": False, "has_stl": False, "has_auto_arima": False, "has_changepoint": False},
}

BASELINE_KRIGING = {
    "task_start": 1700000000,
    "variogram_csv": {"exists": False, "is_new": False, "has_required_columns": False, "parameters_valid": False},
    "variogram_points_csv": {"exists": False, "is_new": False, "row_count": 0},
    "predictions_csv": {"exists": False, "is_new": False, "has_required_columns": False,
                        "values_in_valid_range": False, "row_count": 0},
    "moran_csv": {"exists": False, "is_new": False, "has_required_columns": False},
    "map_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "script": {"modified": False, "has_variogram": False, "has_krige": False, "has_moran": False},
}

# --------------------------------------------------------------------------
# Partial completion JSONs — just one deliverable present, everything else absent
# Expected: score > 0 but < PASS_THRESHOLD (40 is good for partial)
# --------------------------------------------------------------------------

PARTIAL_SEIZURE_GEE = dict(BASELINE_SEIZURE_GEE)
PARTIAL_SEIZURE_GEE.update({
    "model_csv_exists": True,
    "model_csv_is_new": True,
    "model_csv_has_rr_col": True,
    "model_csv_has_pvalue_col": True,
    "model_csv_rr_in_range": True,
})

PARTIAL_GARCH = dict(BASELINE_GARCH)
PARTIAL_GARCH.update({
    "var_csv_exists": True,
    "var_csv_is_new": True,
    "var_csv_has_var95_col": True,
    "var_csv_has_var99_col": True,
    "var_csv_rows": 250,
})

PARTIAL_COX = {
    "task_start": 1700000000,
    "cox_csv": {"exists": True, "is_new": True, "has_hr_column": True,
                "has_pvalue_column": True, "horthy_hr_valid": "true", "row_count": 8},
    "ph_test_csv": {"exists": False, "is_new": False, "has_chisq_column": False, "row_count": 0},
    "km_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "forest_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "script": {"exists": True, "modified": True, "has_coxph": True, "has_cox_zph": False},
}

PARTIAL_CLIMATE = {
    "task_start": 1700000000,
    "stl_csv": {"exists": True, "is_new": True, "has_trend_column": True,
                "trend_is_positive": True, "row_count": 145},
    "forecast_csv": {"exists": False, "is_new": False, "has_required_columns": False,
                     "forecast_values_valid": False, "row_count": 0},
    "breakpoints_csv": {"exists": False, "is_new": False, "has_required_columns": False, "row_count": 0},
    "plot_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "script": {"modified": True, "has_stl": True, "has_auto_arima": False, "has_changepoint": False},
}

PARTIAL_KRIGING = {
    "task_start": 1700000000,
    "variogram_csv": {"exists": True, "is_new": True, "has_required_columns": True, "parameters_valid": True},
    "variogram_points_csv": {"exists": True, "is_new": True, "row_count": 16},
    "predictions_csv": {"exists": False, "is_new": False, "has_required_columns": False,
                        "values_in_valid_range": False, "row_count": 0},
    "moran_csv": {"exists": False, "is_new": False, "has_required_columns": False},
    "map_png": {"exists": False, "is_new": False, "size_bytes": 0, "is_valid_png": False},
    "script": {"modified": True, "has_variogram": True, "has_krige": False, "has_moran": False},
}


# --------------------------------------------------------------------------
# Test runner
# --------------------------------------------------------------------------

def run_test(name, verify_fn, scenario_label, env_info, task_info,
             expect_passed, expect_score_zero=False, expect_score_partial=False):
    """Run a single verifier scenario and report result."""
    try:
        result = verify_fn([], env_info, task_info)
    except Exception as e:
        print(f"  [{name}] {scenario_label}: EXCEPTION — {e}")
        return False

    passed = result.get('passed', False)
    score = result.get('score', -1)
    feedback = result.get('feedback', '')

    if expect_score_zero:
        ok = (not passed) and (score == 0)
        status = "PASS" if ok else "FAIL"
        print(f"  [{name}] {scenario_label}: {status} (score={score}, passed={passed})")
        if not ok:
            print(f"    Expected: passed=False, score=0")
            print(f"    Got feedback: {feedback[:200]}")
        return ok

    if expect_score_partial:
        ok = (not passed) and (0 < score < PASS_THRESHOLD)
        status = "PASS" if ok else "FAIL"
        print(f"  [{name}] {scenario_label}: {status} (score={score}, passed={passed})")
        if not ok:
            print(f"    Expected: passed=False, 0 < score < {PASS_THRESHOLD}")
            print(f"    Got feedback: {feedback[:200]}")
        return ok

    ok = passed == expect_passed
    status = "PASS" if ok else "FAIL"
    print(f"  [{name}] {scenario_label}: {status} (score={score}, passed={passed})")
    if not ok:
        print(f"    Got feedback: {feedback[:200]}")
    return ok


TASKS = [
    ("longitudinal_seizure_gee", verify_longitudinal_seizure_gee,
     BASELINE_SEIZURE_GEE, PARTIAL_SEIZURE_GEE),
    ("garch_financial_risk", verify_garch_financial_risk,
     BASELINE_GARCH, PARTIAL_GARCH),
    ("cox_survival_cancer", verify_cox_survival_cancer,
     BASELINE_COX, PARTIAL_COX),
    ("noaa_climate_forecast", verify_noaa_climate_forecast,
     BASELINE_CLIMATE, PARTIAL_CLIMATE),
    ("spatial_kriging_soil", verify_spatial_kriging_soil,
     BASELINE_KRIGING, PARTIAL_KRIGING),
]


def run_static_tests():
    """Run static (no-VM) do-nothing and partial tests."""
    print("=" * 60)
    print("STATIC PIPELINE TESTS (no VM required)")
    print("=" * 60)

    all_pass = True

    for task_name, verify_fn, baseline, partial in TASKS:
        print(f"\n--- {task_name} ---")

        # Scenario A: export never ran → FileNotFoundError → score=0
        env_info_a = {"copy_from_env": _copy_raises}
        ok_a = run_test(task_name, verify_fn, "A: export never ran",
                        env_info_a, {}, expect_passed=False, expect_score_zero=True)

        # Scenario B: export ran, agent did nothing → baseline JSON → score=0
        env_info_b = {"copy_from_env": _copy_json(baseline)}
        ok_b = run_test(task_name, verify_fn, "B: do-nothing baseline",
                        env_info_b, {}, expect_passed=False, expect_score_zero=True)

        # Scenario C: partial completion → partial JSON → score partial
        env_info_c = {"copy_from_env": _copy_json(partial)}
        ok_c = run_test(task_name, verify_fn, "C: partial deliverable",
                        env_info_c, {}, expect_passed=False, expect_score_partial=True)

        all_pass = all_pass and ok_a and ok_b and ok_c

    print("\n" + "=" * 60)
    status = "ALL PASS" if all_pass else "SOME FAILURES"
    print(f"Static test result: {status}")
    print("=" * 60)
    return all_pass


def run_live_tests():
    """Run live do-nothing test via from_config (requires VM)."""
    try:
        from gym_anything.api import from_config
    except ImportError:
        print("ERROR: gym_anything not importable. Check your Python path.")
        return False

    print("=" * 60)
    print("LIVE DO-NOTHING TESTS (VM required)")
    print("=" * 60)
    print("NOTE: Boots VM once per task; uses pre_task hook to run setup_task.sh")
    print("      Then runs export_result.sh and checks verifier score=0\n")

    all_pass = True

    for task_name, verify_fn, _, _ in TASKS:
        print(f"\n--- {task_name} (live) ---")
        try:
            env = from_config("benchmarks/environments/rstudio_env", task_id=task_name)
            obs = env.reset(seed=42, use_cache=False)
            runner = env._runner

            # Run export script immediately (no agent actions)
            export_out = runner.exec_capture(
                f"bash -l /workspace/tasks/{task_name}/export_result.sh 2>&1"
            )
            print(f"  Export output tail: {export_out[-300:]}")

            copy_fn = lambda src, dst: runner.copy_from(src, dst)
            result = verify_fn([], {"copy_from_env": copy_fn}, {})
            score = result.get("score", -1)
            passed = result.get("passed", True)

            ok = (not passed) and (score == 0)
            print(f"  Live do-nothing: {'PASS' if ok else 'FAIL'} (score={score}, passed={passed})")
            if not ok:
                print(f"  Feedback: {result.get('feedback', '')[:300]}")
            all_pass = all_pass and ok

        except Exception as e:
            print(f"  EXCEPTION: {e}")
            all_pass = False
        finally:
            try:
                env.close()
            except Exception:
                pass

    print("\n" + "=" * 60)
    status = "ALL PASS" if all_pass else "SOME FAILURES"
    print(f"Live test result: {status}")
    print("=" * 60)
    return all_pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pipeline tests for rstudio_env new tasks")
    parser.add_argument("--static", action="store_true", help="Run static tests only (no VM)")
    parser.add_argument("--live", action="store_true", help="Run live VM tests")
    args = parser.parse_args()

    if not args.static and not args.live:
        # Default: run static tests
        args.static = True

    success = True

    if args.static:
        success = run_static_tests() and success

    if args.live:
        success = run_live_tests() and success

    sys.exit(0 if success else 1)
