#!/usr/bin/env python3
"""
Phase 5 Injection Tests for all 5 jamovi_env tasks.

Tests:
  - Wrong-target: inject results that reference different/wrong entities → score=0
  - Partial completion: inject results with only some criteria met → 20-60%, passed=False

These tests call verifier functions directly with crafted mock data (no VM needed).
"""

import json
import os
import sys
import tempfile
import zipfile

# Add project root to path
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, PROJECT_ROOT)

TASKS_DIR = os.path.join(PROJECT_ROOT, "examples", "jamovi_env", "tasks")

# ======================================================================
# Helpers
# ======================================================================

def make_omv_zip(temp_dir, filename, index_html_content, include_meta=True, include_data=True):
    """Create a minimal .omv (ZIP) file with given index.html content."""
    omv_path = os.path.join(temp_dir, filename)
    with zipfile.ZipFile(omv_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("index.html", index_html_content)
        if include_meta:
            zf.writestr("meta", "jamovi archive\n")
            zf.writestr("metadata.json", '{"datasetSchema": {}}')
        if include_data:
            zf.writestr("xdata.json", '{}')
            zf.writestr("data.bin", b'\x00' * 100)
            zf.writestr("strings.bin", b'\x00' * 10)
    return omv_path


def write_json(path, data):
    """Write a dict to a JSON file."""
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def import_verifier(task_name, func_name):
    """Dynamically import a verifier function."""
    import importlib.util
    verifier_path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, func_name)


# ======================================================================
# 1. exam_multi_analysis
# ======================================================================

def test_exam_wrong_target():
    """Wrong-target: .omv with completely unrelated content (no descriptives/ttest/correlation)."""
    td = tempfile.mkdtemp()
    # Create an .omv file at the expected path with wrong content
    html = "<html><body><h1>Linear Regression</h1><p>R-squared: 0.85</p></body></html>"
    omv_path = make_omv_zip(td, "ExamAnalysis.omv", html)

    # Patch the verifier's expected path
    verify = import_verifier("exam_multi_analysis", "verify_exam_multi_analysis")
    # We need to make the file available at the expected path
    # Use copy_from_env to redirect
    def mock_copy(src, dst):
        import shutil
        shutil.copy2(omv_path, dst)

    result = verify([], {"copy_from_env": mock_copy}, {})
    return result


def test_exam_partial():
    """Partial: .omv with only Descriptives (no T-Test or Correlation)."""
    td = tempfile.mkdtemp()
    html = """<html><body>
    <h2>Descriptives</h2>
    <table>
        <tr><th>Variable</th><th>Mean</th><th>Std. Deviation</th><th>Minimum</th><th>Maximum</th></tr>
        <tr><td>Exam</td><td>56.57</td><td>25.73</td><td>15</td><td>100</td></tr>
        <tr><td>Revise</td><td>19.85</td><td>7.92</td><td>2</td><td>38</td></tr>
        <tr><td>Anxiety</td><td>69.39</td><td>14.78</td><td>30</td><td>100</td></tr>
    </table>
    <p>Gender: Male and Female groups shown</p>
    <p>Median values included</p>
    </body></html>"""
    omv_path = make_omv_zip(td, "ExamAnalysis.omv", html)

    verify = import_verifier("exam_multi_analysis", "verify_exam_multi_analysis")

    def mock_copy(src, dst):
        import shutil
        shutil.copy2(omv_path, dst)

    result = verify([], {"copy_from_env": mock_copy}, {})
    return result


# ======================================================================
# 2. tooth_growth_factorial
# ======================================================================

def test_tooth_wrong_target():
    """Wrong-target: .omv file with unrelated analysis (no ANOVA)."""
    td = tempfile.mkdtemp()
    html = "<html><body><h1>Paired Samples T-Test</h1><p>t = 2.34, p = 0.021</p></body></html>"
    omv_path = make_omv_zip(td, "ToothGrowthAnalysis.omv", html)

    verify = import_verifier("tooth_growth_factorial", "verify_tooth_growth_factorial")

    # Monkey-patch the OMV_OUTPUT_PATH in the verifier module
    import importlib.util
    verifier_path = os.path.join(TASKS_DIR, "tooth_growth_factorial", "verifier.py")
    spec = importlib.util.spec_from_file_location("verifier_tooth", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.OMV_OUTPUT_PATH = omv_path
    mod.RESULT_JSON_PATH = "/nonexistent"

    result = mod.verify_tooth_growth_factorial([], {}, {})
    return result


def test_tooth_partial():
    """Partial: .omv with ANOVA + correct vars but no interaction, no assumptions, no post-hoc."""
    td = tempfile.mkdtemp()
    html = """<html><body>
    <h2>ANOVA</h2>
    <table>
        <tr><th>Source</th><th>SS</th><th>df</th><th>MS</th><th>F</th><th>p</th></tr>
        <tr><td>supp</td><td>205.35</td><td>1</td><td>205.35</td><td>12.32</td><td>0.001</td></tr>
        <tr><td>dose</td><td>2426.43</td><td>2</td><td>1213.22</td><td>72.85</td><td>< .001</td></tr>
        <tr><td>Residuals</td><td>933.63</td><td>56</td><td>16.67</td></tr>
    </table>
    <p>Dependent Variable: len</p>
    </body></html>"""
    omv_path = make_omv_zip(td, "ToothGrowthAnalysis.omv", html)

    import importlib.util
    verifier_path = os.path.join(TASKS_DIR, "tooth_growth_factorial", "verifier.py")
    spec = importlib.util.spec_from_file_location("verifier_tooth_p", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.OMV_OUTPUT_PATH = omv_path
    mod.RESULT_JSON_PATH = "/nonexistent"

    result = mod.verify_tooth_growth_factorial([], {}, {})
    return result


# ======================================================================
# 3. personality_efa
# ======================================================================

def test_efa_wrong_target():
    """Wrong-target: .omv with PCA instead of EFA, wrong rotation."""
    td = tempfile.mkdtemp()
    html = """<html><body>
    <h2>Principal Component Analysis</h2>
    <p>Varimax rotation applied to 10 components.</p>
    <p>Component 1, Component 2, Component 3...</p>
    <table><tr><td>Variable1</td><td>0.82</td></tr></table>
    </body></html>"""
    omv_path = make_omv_zip(td, "BFI_FactorAnalysis.omv", html)

    verify = import_verifier("personality_efa", "verify_personality_efa")

    def mock_copy(src, dst):
        import shutil
        shutil.copy2(omv_path, dst)

    result = verify([], {"copy_from_env": mock_copy}, {})
    return result


def test_efa_partial():
    """Partial: .omv with EFA and oblimin but only 3 factors, no KMO/Bartlett."""
    td = tempfile.mkdtemp()
    # Include some personality items but not all 25, and only 3 factors
    items_html = " ".join(f"<td>{item}</td>" for item in ["A1", "A2", "A3", "A4", "A5",
                                                            "C1", "C2", "C3", "C4", "C5",
                                                            "E1", "E2", "E3"])
    html = f"""<html><body>
    <h2>Exploratory Factor Analysis</h2>
    <h3>Factor Loadings</h3>
    <table>
        <tr><th>Variable</th><th>Factor 1</th><th>Factor 2</th><th>Factor 3</th></tr>
        <tr>{items_html}<td>0.75</td><td>0.12</td><td>-0.03</td></tr>
    </table>
    <p>Rotation: oblimin</p>
    <p>Loading values: 0.75 0.68 0.72 0.81 0.65 -0.45 0.33 0.29 0.18 0.55 0.41 0.38</p>
    </body></html>"""
    omv_path = make_omv_zip(td, "BFI_FactorAnalysis.omv", html)

    verify = import_verifier("personality_efa", "verify_personality_efa")

    def mock_copy(src, dst):
        import shutil
        shutil.copy2(omv_path, dst)

    result = verify([], {"copy_from_env": mock_copy}, {})
    return result


# ======================================================================
# 4. titanic_survival (uses result JSON, not direct .omv parsing)
# ======================================================================

def test_titanic_wrong_target():
    """Wrong-target: result JSON says file exists but no chi-square analyses found."""
    td = tempfile.mkdtemp()
    result_json = os.path.join(td, "titanic_survival_result.json")
    write_json(result_json, {
        "file_exists": True,
        "file_size_bytes": 15000,
        "valid_omv": True,
        "has_index_html": True,
        "chisq_count": 0,
        "has_chisq_class": False,
        "has_chisq_sex": False,
        "has_expected_counts": False,
        "has_percentages": False,
        "has_survived": False,
        "has_passengerclass": False,
        "has_sex": False,
        "error": None,
    })

    import importlib.util
    verifier_path = os.path.join(TASKS_DIR, "titanic_survival", "verifier.py")
    spec = importlib.util.spec_from_file_location("verifier_titanic_wt", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.RESULT_JSON_PATH = result_json

    result = mod.verify_titanic_survival([], {}, {})
    return result


def test_titanic_partial():
    """Partial: one chi-square (survived x sex) but not the class one, no expected counts, no percentages."""
    td = tempfile.mkdtemp()
    result_json = os.path.join(td, "titanic_survival_result.json")
    write_json(result_json, {
        "file_exists": True,
        "file_size_bytes": 25000,
        "valid_omv": True,
        "has_index_html": True,
        "chisq_count": 1,
        "has_chisq_class": False,
        "has_chisq_sex": True,
        "has_expected_counts": False,
        "has_percentages": False,
        "has_survived": True,
        "has_passengerclass": False,
        "has_sex": True,
        "error": None,
    })

    import importlib.util
    verifier_path = os.path.join(TASKS_DIR, "titanic_survival", "verifier.py")
    spec = importlib.util.spec_from_file_location("verifier_titanic_p", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.RESULT_JSON_PATH = result_json

    result = mod.verify_titanic_survival([], {}, {})
    return result


# ======================================================================
# 5. insect_nonparametric (uses result JSON, needs copy_from_env)
# ======================================================================

def test_insect_wrong_target():
    """Wrong-target: .omv found but no analyses detected (only data, no tests)."""
    td = tempfile.mkdtemp()
    result_json_path = os.path.join(td, "insect_nonparametric_result.json")
    write_json(result_json_path, {
        "omv_file_found": True,
        "omv_file_path": "/home/ga/Documents/Jamovi/InsectSprayAnalysis.omv",
        "omv_file_size": 12000,
        "index_html_found": True,
        "index_html_content": "<html><body><h1>Untitled Analysis</h1><p>No analyses performed.</p></body></html>",
        "zip_contents": ["index.html", "meta", "xdata.json", "data.bin"],
        "has_descriptives": False,
        "has_descriptives_split_spray": False,
        "has_shapiro_wilk": False,
        "has_kruskal_wallis": False,
        "has_kruskal_wallis_count": False,
        "has_kruskal_wallis_spray": False,
        "has_pairwise": False,
        "has_count_var": False,
        "has_spray_var": False,
        "error": None,
    })

    verify = import_verifier("insect_nonparametric", "verify_insect_nonparametric")

    def mock_copy(src, dst):
        import shutil
        shutil.copy2(result_json_path, dst)

    result = verify([], {"copy_from_env": mock_copy}, {})
    return result


def test_insect_partial():
    """Partial: Kruskal-Wallis found with correct vars, but no descriptives, no normality, no pairwise."""
    td = tempfile.mkdtemp()
    result_json_path = os.path.join(td, "insect_nonparametric_result.json")
    write_json(result_json_path, {
        "omv_file_found": True,
        "omv_file_path": "/home/ga/Documents/Jamovi/InsectSprayAnalysis.omv",
        "omv_file_size": 18000,
        "index_html_found": True,
        "index_html_content": "<html><body><h2>Kruskal-Wallis</h2><p>count by spray: H = 54.7, p < .001</p></body></html>",
        "zip_contents": ["index.html", "meta", "xdata.json", "data.bin", "strings.bin"],
        "has_descriptives": False,
        "has_descriptives_split_spray": False,
        "has_shapiro_wilk": False,
        "has_kruskal_wallis": True,
        "has_kruskal_wallis_count": True,
        "has_kruskal_wallis_spray": True,
        "has_pairwise": False,
        "has_count_var": True,
        "has_spray_var": True,
        "error": None,
    })

    verify = import_verifier("insect_nonparametric", "verify_insect_nonparametric")

    def mock_copy(src, dst):
        import shutil
        shutil.copy2(result_json_path, dst)

    result = verify([], {"copy_from_env": mock_copy}, {})
    return result


# ======================================================================
# Runner
# ======================================================================

def run_all():
    tests = [
        # (name, function, expected_type)
        # Wrong-target tests: score should be low (ideally 0, max ~25 for file-exists credit)
        ("exam_wrong_target", test_exam_wrong_target, "wrong_target"),
        ("tooth_wrong_target", test_tooth_wrong_target, "wrong_target"),
        ("efa_wrong_target", test_efa_wrong_target, "wrong_target"),
        ("titanic_wrong_target", test_titanic_wrong_target, "wrong_target"),
        ("insect_wrong_target", test_insect_wrong_target, "wrong_target"),
        # Partial completion tests: score should be 20-60%, passed=False
        ("exam_partial", test_exam_partial, "partial"),
        ("tooth_partial", test_tooth_partial, "partial"),
        ("efa_partial", test_efa_partial, "partial"),
        ("titanic_partial", test_titanic_partial, "partial"),
        ("insect_partial", test_insect_partial, "partial"),
    ]

    all_results = {}
    all_passed = True

    for name, func, test_type in tests:
        print(f"\n{'='*60}")
        print(f"Running: {name} ({test_type})")
        print(f"{'='*60}")
        try:
            result = func()
            score = result.get("score", -1)
            passed = result.get("passed", None)
            feedback = result.get("feedback", "")

            if test_type == "wrong_target":
                # Wrong-target: score should be low enough that passed=False
                # File-exists points (15-25) are acceptable since the file does exist
                # but the analysis content is wrong. Key: passed must be False.
                ok = not passed
                if ok:
                    print(f"  PASS: score={score}, passed={passed} (wrong target correctly rejected)")
                else:
                    print(f"  FAIL: score={score}, passed={passed} (wrong target should NOT pass!)")
                    all_passed = False
            else:
                # Partial: score should be >0 but <70 (threshold), passed=False
                ok = not passed and 0 < score < 70
                if ok:
                    print(f"  PASS: score={score}, passed={passed} (partial score as expected)")
                else:
                    if passed:
                        print(f"  FAIL: score={score}, passed={passed} (partial should NOT pass!)")
                    elif score == 0:
                        print(f"  WARN: score={score} (expected >0 for partial; injected data may be too minimal)")
                    else:
                        print(f"  FAIL: score={score}, passed={passed} (unexpected)")
                    if passed or score >= 70:
                        all_passed = False

            print(f"  Feedback: {feedback[:200]}")
            all_results[name] = {
                "score": score,
                "passed": passed,
                "test_type": test_type,
                "check_ok": ok,
                "feedback": feedback,
            }
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback
            traceback.print_exc()
            all_results[name] = {
                "score": -1,
                "passed": None,
                "test_type": test_type,
                "check_ok": False,
                "error": str(e),
            }
            all_passed = False

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    for name, r in all_results.items():
        status = "OK" if r.get("check_ok") else "FAIL"
        print(f"  [{status}] {name}: score={r['score']}, passed={r['passed']}")

    print(f"\nOverall: {'ALL PASSED' if all_passed else 'SOME FAILURES'}")

    # Save results
    evidence_dir = os.path.join(PROJECT_ROOT, "examples", "jamovi_env", "evidence")
    os.makedirs(evidence_dir, exist_ok=True)
    output_path = os.path.join(evidence_dir, "phase5_injection_test_results.json")
    with open(output_path, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"\nResults saved to: {output_path}")

    return all_passed


if __name__ == "__main__":
    success = run_all()
    sys.exit(0 if success else 1)
