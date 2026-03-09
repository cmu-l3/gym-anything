#!/usr/bin/env python3
"""
Phase 5 validation tests for all 5 new JASP tasks:
  - Wrong-target tests: inject .jasp with wrong analyses → expect score ≈ 0
  - Partial completion tests: inject .jasp with partial analyses → expect 20-60%

Creates synthetic .jasp files (ZIP archives with analyses.json) and calls
each verifier directly with a mocked copy_from_env.
"""

import json
import os
import shutil
import sys
import tempfile
import zipfile
from datetime import datetime

# Add project root to path so we can import verifiers
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, REPO_ROOT)

TASKS_DIR = os.path.join(REPO_ROOT, "examples", "jasp_env", "tasks")
EVIDENCE_DIR = os.path.join(REPO_ROOT, "examples", "jasp_env", "evidence")


def create_jasp_file(analyses_json_content, output_path, file_size_padding=0,
                     include_resources=False, include_data=False):
    """Create a synthetic .jasp file (ZIP archive) with the given analyses.json content."""
    temp_dir = tempfile.mkdtemp(prefix="jasp_synth_")
    try:
        # Write analyses.json
        analyses_path = os.path.join(temp_dir, "analyses.json")
        with open(analyses_path, "w") as f:
            json.dump(analyses_json_content, f, indent=2)

        # Optionally create resource files to simulate computed results
        if include_resources:
            for i in range(3):
                res_dir = os.path.join(temp_dir, "resources", f"analysis_{i}")
                os.makedirs(res_dir, exist_ok=True)
                results = {
                    "title": f"Analysis {i}",
                    "results": {"t": 2.5, "p": 0.02, "statistic": 3.14},
                    "status": "complete"
                }
                with open(os.path.join(res_dir, "jaspResults.json"), "w") as f:
                    json.dump(results, f)

        # Optionally include a data file
        if include_data:
            with open(os.path.join(temp_dir, "data.csv"), "w") as f:
                f.write("col1,col2\n1,2\n3,4\n")

        # Add padding to reach desired file size
        if file_size_padding > 0:
            with open(os.path.join(temp_dir, "padding.txt"), "w") as f:
                f.write("x" * file_size_padding)

        # Create ZIP
        with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(temp_dir):
                for fname in files:
                    fpath = os.path.join(root, fname)
                    arcname = os.path.relpath(fpath, temp_dir)
                    zf.write(fpath, arcname)
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def make_copy_from_env(jasp_file_path):
    """Create a mock copy_from_env that copies from a local path."""
    def copy_from_env(vm_path, local_path):
        shutil.copy2(jasp_file_path, local_path)
    return copy_from_env


def run_verifier(verifier_func, jasp_path, task_info=None):
    """Run a verifier function with a synthetic .jasp file."""
    env_info = {"copy_from_env": make_copy_from_env(jasp_path)}
    if task_info is None:
        task_info = {"metadata": {}}
    return verifier_func([], env_info, task_info)


# ============================================================
# Verifier imports (use importlib to avoid name collisions)
# ============================================================
import importlib.util

def _load_verifier(task_name, func_name):
    """Load a verifier function from a task directory."""
    verifier_path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, func_name)

verify_paired_samples_analysis = _load_verifier(
    "paired_samples_analysis", "verify_paired_samples_analysis")
verify_factorial_anova_analysis = _load_verifier(
    "factorial_anova_analysis", "verify_factorial_anova_analysis")
verify_regression_model_comparison = _load_verifier(
    "regression_model_comparison", "verify_regression_model_comparison")
verify_exploratory_data_analysis = _load_verifier(
    "exploratory_data_analysis", "verify_exploratory_data_analysis")
verify_nonparametric_group_comparison = _load_verifier(
    "nonparametric_group_comparison", "verify_nonparametric_group_comparison")


# ============================================================
# Test definitions
# ============================================================

def test_paired_samples_wrong_target():
    """Paired samples: t-test with WRONG variables (not Weight Before/After)."""
    analyses = {
        "analyses": [
            {
                "name": "TTestPairedSamples",
                "module": "jaspTTests",
                "analysisType": "TTestPairedSamples",
                "options": {
                    "pairs": [["Score_Pre", "Score_Post"]],
                    "effectSize": False
                }
            }
        ]
    }
    return analyses


def test_paired_samples_partial():
    """Paired samples: t-test with correct vars but NO effect size, NO descriptives."""
    analyses = {
        "analyses": [
            {
                "name": "TTestPairedSamples",
                "module": "jaspTTests",
                "analysisType": "TTestPairedSamples",
                "options": {
                    "pairs": [["Weight Before", "Weight After"]],
                    "effectSize": False
                }
            }
        ]
    }
    return analyses


def test_factorial_anova_wrong_target():
    """Factorial ANOVA: ANOVA with WRONG DV (height instead of len)."""
    analyses = {
        "analyses": [
            {
                "name": "Anova",
                "module": "jaspAnova",
                "analysisType": "Anova",
                "options": {
                    "dependent": "height",
                    "fixedFactors": ["group", "treatment"],
                    "postHocTerms": [{"components": ["treatment"]}],
                    "descriptives": True,
                    "descriptivePlots": True,
                    "plotHorizontalAxis": "treatment",
                    "plotSeparateLines": "group"
                }
            }
        ]
    }
    return analyses


def test_factorial_anova_partial():
    """Factorial ANOVA: correct DV and factors but NO post-hoc, NO descriptives, NO plots."""
    analyses = {
        "analyses": [
            {
                "name": "Anova",
                "module": "jaspAnova",
                "analysisType": "Anova",
                "options": {
                    "dependent": "len",
                    "fixedFactors": ["supp", "dose"],
                    "postHocTerms": [],
                    "descriptives": False,
                    "descriptivePlots": False
                }
            }
        ]
    }
    return analyses


def test_regression_wrong_target():
    """Regression: regression with WRONG DV (not Happiness Score)."""
    analyses = {
        "analyses": [
            {
                "name": "RegressionLinear",
                "module": "jaspRegression",
                "analysis": "RegressionLinear",
                "options": {
                    "dependent": "Income Level",
                    "covariates": ["Population", "Area", "Literacy Rate"],
                    "residualQqPlot": False,
                    "residualVsFittedPlot": False,
                    "collinearityDiagnostic": False
                }
            }
        ]
    }
    return analyses


def test_regression_partial():
    """Regression: correct DV but only 2 covariates, no diagnostic plots."""
    analyses = {
        "analyses": [
            {
                "name": "RegressionLinear",
                "module": "jaspRegression",
                "analysis": "RegressionLinear",
                "options": {
                    "dependent": "Happiness Score",
                    "covariates": ["GDP per Capita", "Family"],
                    "residualQqPlot": False,
                    "residualVsFittedPlot": False,
                    "collinearityDiagnostic": False
                }
            }
        ]
    }
    return analyses


def test_exploratory_wrong_target():
    """EDA: analyses with WRONG variables (not morphometric vars)."""
    analyses = {
        "analyses": [
            {
                "name": "Descriptives",
                "module": "jaspDescriptives",
                "analysisName": "Descriptives",
                "options": {
                    "variables": ["island", "year", "sex"],
                    "splitBy": ["species"]
                }
            },
            {
                "name": "Correlation",
                "module": "jaspRegression",
                "analysisName": "Correlation",
                "options": {
                    "variables": ["island", "year"]
                }
            },
            {
                "name": "Anova",
                "module": "jaspAnova",
                "analysisName": "Anova",
                "options": {
                    "dependent": "year",
                    "fixedFactors": ["island"]
                }
            }
        ]
    }
    return analyses


def test_exploratory_partial():
    """EDA: only descriptives correctly configured, no correlation or ANOVA."""
    analyses = {
        "analyses": [
            {
                "name": "Descriptives",
                "module": "jaspDescriptives",
                "analysisName": "Descriptives",
                "options": {
                    "variables": ["bill_length_mm", "bill_depth_mm", "flipper_length_mm", "body_mass_g"],
                    "splitBy": ["species"],
                    "mean": True,
                    "standardDeviation": True
                }
            }
        ]
    }
    return analyses


def test_nonparametric_wrong_target():
    """Nonparametric: Kruskal-Wallis with WRONG DV and grouping var."""
    analyses = {
        "analyses": [
            {
                "name": "AnovaNonParametric",
                "module": "jaspTTests",
                "options": {
                    "variables": ["Weight"],
                    "groupingVariable": "Treatment",
                    "descriptives": True
                }
            },
            {
                "name": "TTestIndependentSamplesNonParametric",
                "module": "jaspTTests",
                "options": {
                    "variables": ["Weight"],
                    "groupingVariable": "Treatment"
                }
            },
            {
                "name": "Descriptives",
                "module": "jaspDescriptives",
                "options": {
                    "variables": ["Weight"],
                    "splitBy": ["Treatment"]
                }
            }
        ]
    }
    return analyses


def test_nonparametric_partial():
    """Nonparametric: only Kruskal-Wallis correctly configured."""
    analyses = {
        "analyses": [
            {
                "name": "AnovaNonParametric",
                "module": "jaspTTests",
                "options": {
                    "variables": ["Heart Rate"],
                    "groupingVariable": "Group",
                    "descriptives": True
                }
            }
        ]
    }
    return analyses


# ============================================================
# Test runner
# ============================================================

def main():
    results = {}
    all_passed = True
    temp_dir = tempfile.mkdtemp(prefix="jasp_phase5_tests_")

    test_cases = [
        # (task_name, verifier_func, test_name, analyses_gen_func, expected_score_range, expected_passed)
        # WRONG TARGET TESTS - expect score = 0 (wrong-target gate), passed=False
        ("paired_samples_analysis", verify_paired_samples_analysis, "wrong_target",
         test_paired_samples_wrong_target, (0, 0), False),
        ("factorial_anova_analysis", verify_factorial_anova_analysis, "wrong_target",
         test_factorial_anova_wrong_target, (0, 0), False),
        ("regression_model_comparison", verify_regression_model_comparison, "wrong_target",
         test_regression_wrong_target, (0, 0), False),
        ("exploratory_data_analysis", verify_exploratory_data_analysis, "wrong_target",
         test_exploratory_wrong_target, (0, 0), False),
        ("nonparametric_group_comparison", verify_nonparametric_group_comparison, "wrong_target",
         test_nonparametric_wrong_target, (0, 0), False),

        # PARTIAL COMPLETION TESTS - expect 20-60%, passed=False
        ("paired_samples_analysis", verify_paired_samples_analysis, "partial",
         test_paired_samples_partial, (20, 60), False),
        ("factorial_anova_analysis", verify_factorial_anova_analysis, "partial",
         test_factorial_anova_partial, (20, 60), False),
        ("regression_model_comparison", verify_regression_model_comparison, "partial",
         test_regression_partial, (20, 60), False),
        ("exploratory_data_analysis", verify_exploratory_data_analysis, "partial",
         test_exploratory_partial, (15, 60), False),
        ("nonparametric_group_comparison", verify_nonparametric_group_comparison, "partial",
         test_nonparametric_partial, (15, 55), False),
    ]

    print("=" * 80)
    print("PHASE 5 VALIDATION TESTS - Wrong-Target and Partial Completion")
    print("=" * 80)

    for task_name, verifier_func, test_type, gen_func, score_range, expected_passed in test_cases:
        test_id = f"{task_name}_{test_type}"
        print(f"\n--- {test_id} ---")

        # Create synthetic .jasp file
        analyses = gen_func()
        jasp_path = os.path.join(temp_dir, f"{test_id}.jasp")
        create_jasp_file(
            analyses,
            jasp_path,
            file_size_padding=6000 if test_type == "partial" else 200,
            include_resources=(test_type == "partial"),
        )

        # Run verifier
        try:
            result = run_verifier(verifier_func, jasp_path)
            score = result.get("score", -1)
            passed = result.get("passed", None)
            feedback = result.get("feedback", "")

            # Validate expectations
            score_ok = score_range[0] <= score <= score_range[1]
            passed_ok = passed == expected_passed

            test_passed = score_ok and passed_ok
            if not test_passed:
                all_passed = False

            status = "PASS" if test_passed else "FAIL"
            print(f"  Status: {status}")
            print(f"  Score: {score} (expected range: {score_range[0]}-{score_range[1]}) {'OK' if score_ok else 'UNEXPECTED'}")
            print(f"  Passed: {passed} (expected: {expected_passed}) {'OK' if passed_ok else 'UNEXPECTED'}")
            print(f"  Feedback: {feedback[:200]}...")

            results[test_id] = {
                "status": status,
                "score": score,
                "passed": passed,
                "expected_score_range": list(score_range),
                "expected_passed": expected_passed,
                "score_in_range": score_ok,
                "passed_matches": passed_ok,
                "feedback": feedback,
            }
        except Exception as e:
            print(f"  ERROR: {e}")
            results[test_id] = {
                "status": "ERROR",
                "error": str(e),
            }
            all_passed = False

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)

    pass_count = sum(1 for r in results.values() if r.get("status") == "PASS")
    fail_count = sum(1 for r in results.values() if r.get("status") == "FAIL")
    error_count = sum(1 for r in results.values() if r.get("status") == "ERROR")

    print(f"  Total: {len(results)}")
    print(f"  Passed: {pass_count}")
    print(f"  Failed: {fail_count}")
    print(f"  Errors: {error_count}")
    print(f"  Overall: {'ALL PASS' if all_passed else 'SOME FAILURES'}")

    # Save results to evidence
    os.makedirs(EVIDENCE_DIR, exist_ok=True)
    evidence_path = os.path.join(EVIDENCE_DIR, "phase5_validation_results.json")
    evidence = {
        "test_type": "Phase 5 Validation (Wrong-Target + Partial Completion)",
        "timestamp": datetime.now().isoformat(),
        "overall_pass": all_passed,
        "summary": {
            "total": len(results),
            "passed": pass_count,
            "failed": fail_count,
            "errors": error_count,
        },
        "results": results,
    }
    with open(evidence_path, "w") as f:
        json.dump(evidence, f, indent=2)

    print(f"\n  Evidence saved to: {evidence_path}")

    # Cleanup
    shutil.rmtree(temp_dir, ignore_errors=True)

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
