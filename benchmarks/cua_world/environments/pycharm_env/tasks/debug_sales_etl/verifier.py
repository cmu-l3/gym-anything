import json
import os
import tempfile


def verify_debug_sales_etl(traj, env_info, task_info):
    """
    Verify that the agent fixed all 3 bugs in the sales ETL pipeline:
      Bug 1 (30 pts): parse_date used wrong strptime format ("%m/%d/%Y" instead of "%Y-%m-%d")
      Bug 2 (30 pts): apply_discount formula was wrong (price * pct/100 instead of price * (1 - pct/100))
      Bug 3 (30 pts): save_transaction INSERT had quantity and unit_price columns swapped
      Bonus (10 pts): no regression in previously-passing tests
    Pass threshold: 65 (must fix at least 2 of 3 bugs)
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available — cannot retrieve results from environment",
        }

    task_name = "debug_sales_etl"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result JSON malformed: {e}",
        }

    score = 0
    parts = []
    feedback_details = []

    # --- Criterion 1: Bug 1 fixed (parse_date format) ---
    bug1_fixed = result.get("bug1_fixed_parse_date", False)
    test_parse_pass = result.get("test_parse_date_pass", False)
    # Accept either static analysis finding OR the specific test passing
    if bug1_fixed or test_parse_pass:
        score += 30
        parts.append("Bug 1 fixed: parse_date now uses correct ISO date format (30/30)")
    else:
        feedback_details.append(
            "Bug 1 NOT fixed: parse_date still uses wrong strptime format — "
            "test_parse_date_iso_format is still failing"
        )

    # --- Criterion 2: Bug 2 fixed (apply_discount formula) ---
    bug2_fixed = result.get("bug2_fixed_apply_discount", False)
    test_discount_pass = result.get("test_discount_pass", False)
    if bug2_fixed or test_discount_pass:
        score += 30
        parts.append("Bug 2 fixed: apply_discount formula correctly computes discounted price (30/30)")
    else:
        feedback_details.append(
            "Bug 2 NOT fixed: apply_discount still returns price * pct/100 "
            "instead of price * (1 - pct/100) — test_apply_discount_ten_percent is still failing"
        )

    # --- Criterion 3: Bug 3 fixed (save_transaction column order) ---
    bug3_fixed = result.get("bug3_fixed_save_transaction", False)
    test_load_pass = result.get("test_load_pass", False)
    if bug3_fixed or test_load_pass:
        score += 30
        parts.append("Bug 3 fixed: save_transaction INSERT columns are in correct order (30/30)")
    else:
        feedback_details.append(
            "Bug 3 NOT fixed: save_transaction still has quantity and unit_price swapped in INSERT — "
            "test_save_and_retrieve_quantity is still failing"
        )

    # --- Criterion 4: No regression in previously-passing tests ---
    no_regression = result.get("no_regression", False)
    if no_regression:
        score += 10
        parts.append("No regression: all previously-passing tests still pass (+10)")
    else:
        feedback_details.append(
            "Regression detected: one or more previously-passing tests now fail. "
            "Fixes must not break extract or other transform tests."
        )

    score = min(score, 100)
    passed = score >= 65

    # Build final feedback
    all_feedback = parts + feedback_details
    if not all_feedback:
        all_feedback = ["No criteria met"]

    tests_passed = result.get("tests_passed", 0)
    tests_total = result.get("tests_total", 0)
    summary = f"Score: {score}/100 | Tests: {tests_passed}/{tests_total} passing"

    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | " + " | ".join(all_feedback),
    }
