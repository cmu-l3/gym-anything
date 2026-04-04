"""
Verifier for hr_workforce_analytics task.

Occupation: HR Analytics Manager (SOC 11-3121.00)
Context: Build a workforce analytics summary table and stored procedure in
         AdventureWorks2022 using ROW_NUMBER(), conditional aggregation, and DATEDIFF.
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_hr_workforce_analytics(traj, env_info, task_info):
    """
    Score the hr_workforce_analytics task.

    Expected objects in AdventureWorks2022:
    - HumanResources.WorkforceSummary table (13 columns with index)
    - HumanResources.usp_RefreshWorkforceSummary stored procedure
    - Table populated with one row per department
    """
    copy_from_env = env_info.get("copy_from_env")

    # ── Copy result JSON from VM ───────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/hr_workforce_result.json", tmp.name)
    except Exception as e:
        os.unlink(tmp.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No result file found. export_result.sh may not have run. Error: {e}",
            "subscores": {},
        }

    try:
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        os.unlink(tmp.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result JSON: {e}",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    # ── GATE: Wrong-target detection ──────────────────────────────────────────
    table_exists = result.get("table_exists", False)
    proc_exists = result.get("proc_exists", False)

    if not table_exists and not proc_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: Neither HumanResources.WorkforceSummary nor "
                "HumanResources.usp_RefreshWorkforceSummary were found in AdventureWorks2022. "
                "The agent may have worked on the wrong database or created no objects at all."
            ),
            "subscores": {"gate": 0},
        }

    # ── Criterion 1: WorkforceSummary table exists (20 pts) ───────────────────
    if table_exists:
        score += 20
        subscores["table_exists"] = 20
        feedback_parts.append("PASS: HumanResources.WorkforceSummary table exists.")
    else:
        subscores["table_exists"] = 0
        feedback_parts.append("FAIL: HumanResources.WorkforceSummary table not found.")

    # ── Criterion 2: Table has required columns (20 pts) ──────────────────────
    has_required_columns = result.get("has_required_columns", False)
    required_column_count = result.get("required_column_count", 0)
    columns_found = result.get("columns_found", "")

    if has_required_columns:
        score += 20
        subscores["table_columns"] = 20
        feedback_parts.append(
            "PASS: WorkforceSummary has required columns (DepartmentID, DepartmentName, "
            "ActiveEmployeeCount, AvgHourlyRate, FemaleCount, MaleCount, AvgTenureDays, "
            "SeniorEmployeeCount)."
        )
    elif table_exists and required_column_count > 0:
        partial = min(15, int(required_column_count / 8 * 20))
        score += partial
        subscores["table_columns"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {required_column_count}/8 required columns found. "
            f"Columns present: {columns_found}"
        )
    else:
        subscores["table_columns"] = 0
        feedback_parts.append(
            "FAIL: Column check could not be performed (table missing or no columns found)."
        )

    # ── Criterion 3: Table is populated with data (20 pts) ────────────────────
    table_row_count = result.get("table_row_count", 0)

    if table_exists and table_row_count >= 8:
        score += 20
        subscores["table_data"] = 20
        feedback_parts.append(
            f"PASS: WorkforceSummary has {table_row_count} department rows "
            f"(stored procedure executed and populated all departments)."
        )
    elif table_exists and table_row_count >= 3:
        score += 12
        subscores["table_data"] = 12
        feedback_parts.append(
            f"PARTIAL: WorkforceSummary has {table_row_count} rows (expected >= 8 for all departments). "
            f"Did you EXEC HumanResources.usp_RefreshWorkforceSummary?"
        )
    elif table_exists and table_row_count > 0:
        score += 5
        subscores["table_data"] = 5
        feedback_parts.append(
            f"PARTIAL: WorkforceSummary has only {table_row_count} rows. "
            f"Check your JOIN conditions in the stored procedure."
        )
    else:
        subscores["table_data"] = 0
        feedback_parts.append(
            "FAIL: WorkforceSummary has no data. "
            "Execute: EXEC HumanResources.usp_RefreshWorkforceSummary"
        )

    # ── Criterion 4: Stored procedure exists (15 pts) ─────────────────────────
    if proc_exists:
        score += 15
        subscores["stored_proc"] = 15
        feedback_parts.append("PASS: Stored procedure HumanResources.usp_RefreshWorkforceSummary exists.")
    else:
        subscores["stored_proc"] = 0
        feedback_parts.append("FAIL: Stored procedure HumanResources.usp_RefreshWorkforceSummary not found.")

    # ── Criterion 5: Gender counts are internally consistent (10 pts) ─────────
    gender_counts_valid = result.get("gender_counts_valid", False)

    if gender_counts_valid:
        score += 10
        subscores["gender_counts"] = 10
        feedback_parts.append(
            "PASS: FemaleCount + MaleCount equals ActiveEmployeeCount "
            "(conditional aggregation is correct)."
        )
    elif table_exists and table_row_count > 0:
        subscores["gender_counts"] = 0
        feedback_parts.append(
            "FAIL: FemaleCount + MaleCount does not equal ActiveEmployeeCount. "
            "Use SUM(CASE WHEN e.Gender = 'F' THEN 1 ELSE 0 END) for FemaleCount."
        )
    else:
        subscores["gender_counts"] = 0
        feedback_parts.append("FAIL: Gender count check skipped (no data in table).")

    # ── Criterion 6: Hourly rate values are valid (5 pts) ─────────────────────
    hourly_rate_valid = result.get("hourly_rate_valid", False)

    if hourly_rate_valid:
        score += 5
        subscores["hourly_rate"] = 5
        feedback_parts.append(
            "PASS: AvgHourlyRate has positive values (pay history join is correct)."
        )
    elif table_exists and table_row_count > 0:
        subscores["hourly_rate"] = 0
        feedback_parts.append(
            "FAIL: AvgHourlyRate is 0 or NULL. "
            "Use ROW_NUMBER() OVER (PARTITION BY BusinessEntityID ORDER BY RateChangeDate DESC) "
            "to get the most recent pay rate per employee."
        )
    else:
        subscores["hourly_rate"] = 0
        feedback_parts.append("FAIL: Hourly rate check skipped (no data in table).")

    # ── Criterion 7: Department names cross-validate with source data (5 pts) ──
    dept_name_match_count = result.get("dept_name_match_count", 0)

    if dept_name_match_count >= 2:
        score += 5
        subscores["dept_name_validation"] = 5
        feedback_parts.append(
            f"PASS: {dept_name_match_count}/3 top department names match HumanResources.Department "
            f"(data integrity confirmed)."
        )
    else:
        subscores["dept_name_validation"] = 0
        feedback_parts.append(
            f"FAIL: Only {dept_name_match_count}/3 department names match HumanResources.Department. "
            f"Verify the JOIN to HumanResources.Department and that DepartmentName comes from d.Name."
        )

    # ── Criterion 8: Non-clustered index on DepartmentID (5 pts) ──────────────
    index_exists = result.get("index_exists", False)

    if index_exists:
        score += 5
        subscores["index"] = 5
        feedback_parts.append(
            "PASS: Non-clustered index on HumanResources.WorkforceSummary(DepartmentID) exists."
        )
    elif table_exists:
        subscores["index"] = 0
        feedback_parts.append(
            "FAIL: Non-clustered index on DepartmentID not found. "
            "Use: CREATE NONCLUSTERED INDEX IX_WorkforceSummary_DeptID "
            "ON HumanResources.WorkforceSummary (DepartmentID)."
        )
    else:
        subscores["index"] = 0
        feedback_parts.append("FAIL: Index check skipped (table does not exist).")

    # ── Final verdict ─────────────────────────────────────────────────────────
    passed = score >= PASS_THRESHOLD
    feedback = " | ".join(feedback_parts)

    if passed:
        feedback = f"PASSED ({score}/100): " + feedback
    else:
        feedback = f"FAILED ({score}/100, need {PASS_THRESHOLD}): " + feedback

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
    }
