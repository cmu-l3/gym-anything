"""
Verifier for vendor_performance_analytics task.

Occupation: Logistics Analyst (SOC 13-1081.02)
Context: Build a vendor performance analytics system in AdventureWorks2022 using
         schema creation, stored procedures, window functions, and multi-schema joins.
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_vendor_performance_analytics(traj, env_info, task_info):
    """
    Score the vendor_performance_analytics task.

    Expected objects in AdventureWorks2022:
    - Analytics schema
    - Analytics.VendorPerformance table (7 columns)
    - dbo.usp_VendorPerformanceReport stored procedure
    - Table populated with data for '2013-01-01' to '2014-01-01'
    """
    copy_from_env = env_info.get("copy_from_env")

    # ── Copy result JSON from VM ───────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/vendor_perf_result.json", tmp.name)
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
    # If neither Analytics schema nor the stored procedure exists, the agent worked
    # on the wrong database or created completely wrong objects.
    schema_exists = result.get("analytics_schema_exists", False)
    proc_exists = result.get("proc_exists", False)
    table_exists = result.get("vp_table_exists", False)

    if not schema_exists and not proc_exists and not table_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: Neither the Analytics schema, the Analytics.VendorPerformance table, "
                "nor the stored procedure dbo.usp_VendorPerformanceReport were found in "
                "AdventureWorks2022. The agent may have worked on the wrong database or created "
                "no objects at all."
            ),
            "subscores": {"gate": 0},
        }

    # ── Criterion 1: Analytics schema exists (10 pts) ─────────────────────────
    if schema_exists:
        score += 10
        subscores["analytics_schema"] = 10
        feedback_parts.append("PASS: Analytics schema exists in AdventureWorks2022.")
    else:
        subscores["analytics_schema"] = 0
        feedback_parts.append("FAIL: Analytics schema not found in AdventureWorks2022.")

    # ── Criterion 2: VendorPerformance table exists (15 pts) ─────────────────
    if table_exists:
        score += 15
        subscores["vp_table"] = 15
        feedback_parts.append("PASS: Analytics.VendorPerformance table exists.")
    else:
        subscores["vp_table"] = 0
        feedback_parts.append("FAIL: Analytics.VendorPerformance table not found.")

    # ── Criterion 3: Stored procedure exists (20 pts) ─────────────────────────
    if proc_exists:
        score += 20
        subscores["stored_proc"] = 20
        feedback_parts.append("PASS: Stored procedure dbo.usp_VendorPerformanceReport exists.")
    else:
        subscores["stored_proc"] = 0
        feedback_parts.append("FAIL: Stored procedure dbo.usp_VendorPerformanceReport not found.")

    # ── Criterion 4: All 7 required columns present (15 pts) ─────────────────
    has_required_columns = result.get("has_required_columns", False)
    column_count = result.get("column_count", 0)
    columns_found = result.get("columns_found", "")

    if has_required_columns:
        score += 15
        subscores["required_columns"] = 15
        feedback_parts.append(
            f"PASS: All 7 required columns found in Analytics.VendorPerformance "
            f"(VendorID, VendorName, TotalOrders, TotalLineItems, AvgUnitCostVariance, "
            f"OnTimeDeliveryRate, VendorRank)."
        )
    elif table_exists and column_count > 0:
        # Partial credit: found some but not all columns
        partial = min(10, int(column_count / 7 * 15))
        score += partial
        subscores["required_columns"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {column_count}/7 required columns found in Analytics.VendorPerformance. "
            f"Columns found: {columns_found}"
        )
    else:
        subscores["required_columns"] = 0
        feedback_parts.append(
            "FAIL: Required columns check could not be performed (table missing or no columns found)."
        )

    # ── Criterion 5: Table populated with data (15 pts) ───────────────────────
    vp_row_count = result.get("vp_row_count", 0)
    has_data = result.get("has_data", False)

    if has_data and vp_row_count >= 5:
        score += 15
        subscores["data_populated"] = 15
        feedback_parts.append(
            f"PASS: Analytics.VendorPerformance has {vp_row_count} rows of vendor data."
        )
    elif has_data and vp_row_count > 0:
        score += 8
        subscores["data_populated"] = 8
        feedback_parts.append(
            f"PARTIAL: Analytics.VendorPerformance has only {vp_row_count} rows "
            f"(expected >= 5 for 2013-01-01 to 2014-01-01 date range)."
        )
    else:
        subscores["data_populated"] = 0
        feedback_parts.append(
            "FAIL: Analytics.VendorPerformance has no data. Did you execute the stored procedure?"
        )

    # ── Criterion 6: VendorRank uses proper DENSE_RANK (sequential) (10 pts) ──
    vendor_rank_valid = result.get("vendor_rank_valid", False)

    if vendor_rank_valid:
        score += 10
        subscores["vendor_rank"] = 10
        feedback_parts.append(
            "PASS: VendorRank column uses DENSE_RANK correctly (sequential integers starting at 1)."
        )
    elif has_data:
        subscores["vendor_rank"] = 0
        rank_min = result.get("rank_min", "?")
        rank_max = result.get("rank_max", "?")
        feedback_parts.append(
            f"FAIL: VendorRank is not a proper DENSE_RANK sequence "
            f"(min={rank_min}, max={rank_max}). Expected min=1 and max=distinct_rank_count."
        )
    else:
        subscores["vendor_rank"] = 0
        feedback_parts.append("FAIL: VendorRank check skipped (no data in table).")

    # ── Criterion 7: OnTimeDeliveryRate values between 0 and 1 (10 pts) ───────
    delivery_rate_valid = result.get("delivery_rate_valid", False)

    if delivery_rate_valid:
        score += 10
        subscores["delivery_rate"] = 10
        rate_min = result.get("rate_min", "?")
        rate_max = result.get("rate_max", "?")
        feedback_parts.append(
            f"PASS: OnTimeDeliveryRate values are valid fractions between 0 and 1 "
            f"(min={rate_min}, max={rate_max})."
        )
    elif has_data:
        subscores["delivery_rate"] = 0
        rate_min = result.get("rate_min", "?")
        rate_max = result.get("rate_max", "?")
        feedback_parts.append(
            f"FAIL: OnTimeDeliveryRate values outside expected range [0.0, 1.0] "
            f"(min={rate_min}, max={rate_max}). "
            f"Use CAST(SUM(...)/COUNT(...) AS DECIMAL(18,4)) for the fraction."
        )
    else:
        subscores["delivery_rate"] = 0
        feedback_parts.append("FAIL: OnTimeDeliveryRate check skipped (no data in table).")

    # ── Criterion 8: VendorName cross-validation (5 pts) ─────────────────────
    vendor_name_match_count = result.get("vendor_name_match_count", 0)

    if vendor_name_match_count >= 2:
        score += 5
        subscores["vendor_name_validation"] = 5
        feedback_parts.append(
            f"PASS: {vendor_name_match_count}/3 vendor names in the table match actual vendors "
            f"in Purchasing.Vendor (data integrity confirmed)."
        )
    else:
        subscores["vendor_name_validation"] = 0
        feedback_parts.append(
            f"FAIL: Only {vendor_name_match_count}/3 top vendor names match Purchasing.Vendor. "
            f"Verify the JOIN to Purchasing.Vendor and that VendorName comes from v.Name."
        )

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
