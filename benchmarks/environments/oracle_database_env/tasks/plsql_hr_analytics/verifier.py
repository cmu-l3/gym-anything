"""
Verifier for plsql_hr_analytics task.

Scoring breakdown (100 pts total):
- HR_ANALYTICS package exists and is VALID (10 pts)
- DEPT_SALARY_STATS function exists (10 pts)
  + returns correct AVG:nnn|MIN:nnn|MAX:nnn format (10 pts)
- BUILD_COMPENSATION_MATRIX procedure exists (5 pts)
  + COMPENSATION_MATRIX table created with >= 100 rows (10 pts)
  + table has required columns: EMPLOYEE_ID, FULL_NAME, JOB_TITLE,
    CURRENT_SALARY, DEPT_AVG_SALARY, SALARY_DEVIATION_PCT, GRADE_LEVEL (10 pts)
  + GRADE_LEVEL values are valid A-E (5 pts)
- REPORTING_CHAIN function exists (5 pts)
  + returns pipe-delimited chain (10 pts)
- compensation_matrix.txt file exists on Desktop with >= 100 lines (10 pts)
  + file contains structured data (column headers or values) (5 pts)

Pass threshold: 60 pts
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_plsql_hr_analytics(traj, env_info, task_info):
    """
    Verifies the plsql_hr_analytics task.
    Agent must create an HR_ANALYTICS PL/SQL package with three components
    and export a compensation matrix to a desktop file.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "score": 0.0,
            "passed": False,
            "feedback": "copy_from_env not available in env_info"
        }

    # Copy result JSON from VM
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "plsql_hr_analytics_result.json")
        try:
            copy_from_env("/tmp/plsql_hr_analytics_result.json", result_path)
        except Exception as e:
            return {
                "score": 0.0,
                "passed": False,
                "feedback": f"Could not retrieve result file: {e}. Export script may have failed."
            }

        if not os.path.exists(result_path):
            return {
                "score": 0.0,
                "passed": False,
                "feedback": "Result file not found after copy."
            }

        try:
            with open(result_path, "r") as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {
                "score": 0.0,
                "passed": False,
                "feedback": f"Result JSON is malformed: {e}"
            }

    score = 0
    feedback_parts = []

    # --- (1) Package existence and validity (10 pts) ---
    if result.get("package_exists"):
        if result.get("package_status") == "VALID":
            score += 10
            feedback_parts.append("HR_ANALYTICS package: EXISTS and VALID (+10)")
        else:
            score += 3
            status = result.get("package_status", "UNKNOWN")
            feedback_parts.append(f"HR_ANALYTICS package: EXISTS but status={status} — compilation errors? (+3)")
    else:
        feedback_parts.append("HR_ANALYTICS package: NOT FOUND (0 pts for this criterion)")
        # If package doesn't exist, most other checks will also fail
        return {
            "score": 0.0,
            "passed": False,
            "feedback": "HR_ANALYTICS package not found. " + " | ".join(feedback_parts)
        }

    # --- (2) DEPT_SALARY_STATS function (10 + 10 pts) ---
    if result.get("dept_salary_stats_exists"):
        score += 10
        feedback_parts.append("DEPT_SALARY_STATS: exists (+10)")

        # Test the output format: should match AVG:nnn|MIN:nnn|MAX:nnn
        test_output = result.get("dept_salary_stats_test", "")
        if test_output and not test_output.startswith("ERROR"):
            # Check format
            if re.match(r"AVG:\d+(\.\d+)?\|MIN:\d+(\.\d+)?\|MAX:\d+(\.\d+)?", test_output):
                score += 10
                feedback_parts.append(f"DEPT_SALARY_STATS format: CORRECT '{test_output}' (+10)")
            else:
                score += 3
                feedback_parts.append(f"DEPT_SALARY_STATS format: unexpected '{test_output[:100]}' — expected AVG:n|MIN:n|MAX:n (+3 partial)")
        elif test_output.startswith("ERROR"):
            feedback_parts.append(f"DEPT_SALARY_STATS execution error: {test_output[:150]}")
        else:
            feedback_parts.append("DEPT_SALARY_STATS: no test output (package may be invalid)")
    else:
        feedback_parts.append("DEPT_SALARY_STATS: function not found in package (0 pts)")

    # --- (3) BUILD_COMPENSATION_MATRIX procedure (5 + 10 + 10 + 5 pts) ---
    if result.get("build_compensation_matrix_exists"):
        score += 5
        feedback_parts.append("BUILD_COMPENSATION_MATRIX: exists (+5)")
    else:
        feedback_parts.append("BUILD_COMPENSATION_MATRIX: procedure not found (0 pts)")

    if result.get("compensation_matrix_table_exists"):
        row_count = result.get("compensation_table_row_count", 0)
        if row_count >= 100:
            score += 10
            feedback_parts.append(f"COMPENSATION_MATRIX table: {row_count} rows (>=100 required) (+10)")
        elif row_count > 0:
            score += 4
            feedback_parts.append(f"COMPENSATION_MATRIX table: only {row_count} rows (<100) (+4 partial)")
        else:
            score += 1
            feedback_parts.append("COMPENSATION_MATRIX table: exists but empty (+1)")

        # Check required columns
        required_cols = {"EMPLOYEE_ID", "FULL_NAME", "JOB_TITLE",
                        "CURRENT_SALARY", "DEPT_AVG_SALARY",
                        "SALARY_DEVIATION_PCT", "GRADE_LEVEL"}
        actual_cols = set(result.get("compensation_table_columns", []))
        missing_cols = required_cols - actual_cols
        if not missing_cols:
            score += 10
            feedback_parts.append(f"COMPENSATION_MATRIX columns: all 7 required columns present (+10)")
        elif len(missing_cols) <= 2:
            score += 5
            feedback_parts.append(f"COMPENSATION_MATRIX columns: missing {missing_cols} (+5 partial)")
        else:
            feedback_parts.append(f"COMPENSATION_MATRIX columns: missing {missing_cols} (0 pts)")

        # Check GRADE_LEVEL values are valid (A-E)
        grade_levels = result.get("grade_levels_present", [])
        valid_grades = {"A", "B", "C", "D", "E"}
        if grade_levels and all(g in valid_grades for g in grade_levels):
            score += 5
            feedback_parts.append(f"GRADE_LEVEL values: {grade_levels} — all valid A-E (+5)")
        elif grade_levels:
            invalid = [g for g in grade_levels if g not in valid_grades]
            feedback_parts.append(f"GRADE_LEVEL values: found invalid grades {invalid} (0 pts)")
        else:
            feedback_parts.append("GRADE_LEVEL column: no values or column absent (0 pts)")
    else:
        feedback_parts.append("COMPENSATION_MATRIX table: not created (0 pts for table checks)")

    # --- (4) REPORTING_CHAIN function (5 + 10 pts) ---
    if result.get("reporting_chain_exists"):
        score += 5
        feedback_parts.append("REPORTING_CHAIN: exists (+5)")

        chain_output = result.get("reporting_chain_test", "")
        if chain_output and not chain_output.startswith("ERROR"):
            # Should return a pipe-delimited chain of names
            if "|" in chain_output and len(chain_output) > 5:
                score += 10
                feedback_parts.append(f"REPORTING_CHAIN output: '{chain_output[:120]}' — pipe-delimited chain found (+10)")
            elif len(chain_output) > 0:
                score += 3
                feedback_parts.append(f"REPORTING_CHAIN output: '{chain_output[:100]}' — no pipes found, expected pipe-delimited (+3 partial)")
        elif chain_output.startswith("ERROR"):
            feedback_parts.append(f"REPORTING_CHAIN execution error: {chain_output[:150]}")
        else:
            feedback_parts.append("REPORTING_CHAIN: no test output")
    else:
        feedback_parts.append("REPORTING_CHAIN: function not found in package (0 pts)")

    # --- (5) compensation_matrix.txt desktop file (10 + 5 pts) ---
    if result.get("compensation_matrix_file_exists"):
        file_size = result.get("compensation_matrix_file_size", 0)
        line_count = result.get("compensation_matrix_file_line_count", 0)
        if line_count >= 100 or file_size > 2000:
            score += 10
            feedback_parts.append(f"compensation_matrix.txt: exists, {line_count} lines, {file_size} bytes (+10)")
        else:
            score += 3
            feedback_parts.append(f"compensation_matrix.txt: exists but only {line_count} lines / {file_size} bytes (+3 partial)")

        preview = result.get("compensation_matrix_file_preview", "")
        # Check that file looks like structured data (has numbers, names)
        if preview and (re.search(r"\d{3,}", preview) or re.search(r"[A-Z]{2,}", preview)):
            score += 5
            feedback_parts.append("compensation_matrix.txt: contains structured data (+5)")
        else:
            feedback_parts.append("compensation_matrix.txt: content appears empty or unstructured (0 pts)")
    else:
        feedback_parts.append("compensation_matrix.txt: NOT found at /home/ga/Desktop/ (0 pts)")

    # Final score
    max_score = 100
    normalized = round(score / max_score, 4)
    passed = score >= 60

    return {
        "score": normalized,
        "passed": passed,
        "raw_score": score,
        "max_score": max_score,
        "feedback": " | ".join(feedback_parts)
    }
