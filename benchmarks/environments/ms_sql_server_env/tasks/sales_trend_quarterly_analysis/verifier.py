"""
Verifier for sales_trend_quarterly_analysis task.

Occupation: Business Intelligence Analyst (SOC 15-2051.01)
Context: Build a quarter-over-quarter sales trend view in AdventureWorks2022
         using LAG() window function, DENSE_RANK(), and export top performers to CSV.
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_sales_trend_quarterly_analysis(traj, env_info, task_info):
    """
    Score the sales_trend_quarterly_analysis task.

    Expected objects in AdventureWorks2022:
    - dbo.vw_SalesPersonQuarterlyTrend view (10 columns including LAG and DENSE_RANK)
    - /home/ga/Documents/exports/top_sales_trends.csv (5 data rows)
    """
    copy_from_env = env_info.get("copy_from_env")

    # ── Copy result JSON from VM ───────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/sales_trend_result.json", tmp.name)
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
    view_exists = result.get("view_exists", False)
    csv_exists = result.get("csv_exists", False)

    if not view_exists and not csv_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: Neither the view dbo.vw_SalesPersonQuarterlyTrend nor the CSV file "
                "/home/ga/Documents/exports/top_sales_trends.csv were found. "
                "The agent may have worked on the wrong database or created no objects at all."
            ),
            "subscores": {"gate": 0},
        }

    # ── Criterion 1: View exists (15 pts) ─────────────────────────────────────
    if view_exists:
        score += 15
        subscores["view_exists"] = 15
        feedback_parts.append("PASS: View dbo.vw_SalesPersonQuarterlyTrend exists in AdventureWorks2022.")
    else:
        subscores["view_exists"] = 0
        feedback_parts.append("FAIL: View dbo.vw_SalesPersonQuarterlyTrend not found in AdventureWorks2022.")

    # ── Criterion 2: View has required columns (20 pts) ───────────────────────
    has_required_columns = result.get("has_required_columns", False)
    required_column_count = result.get("required_column_count", 0)
    columns_found = result.get("columns_found", "")

    if has_required_columns:
        score += 20
        subscores["required_columns"] = 20
        feedback_parts.append(
            f"PASS: All required columns found in vw_SalesPersonQuarterlyTrend "
            f"(SalesPersonID, FirstName, LastName, TerritoryName, CalendarYear, "
            f"CalendarQuarter, QuarterlySales, PrevQuarterSales, QoQGrowthPct, SalesRankInTerritory)."
        )
    elif view_exists and required_column_count > 0:
        partial = min(15, int(required_column_count / 10 * 20))
        score += partial
        subscores["required_columns"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {required_column_count}/10 required columns found in view. "
            f"Columns found: {columns_found}"
        )
    else:
        subscores["required_columns"] = 0
        feedback_parts.append(
            "FAIL: Required columns check could not be performed (view missing or no columns found)."
        )

    # ── Criterion 3: View has meaningful data (10 pts) ────────────────────────
    view_row_count = result.get("view_row_count", 0)

    if view_exists and view_row_count >= 50:
        score += 10
        subscores["view_data"] = 10
        feedback_parts.append(
            f"PASS: View contains {view_row_count} rows of quarterly sales data."
        )
    elif view_exists and view_row_count > 0:
        score += 5
        subscores["view_data"] = 5
        feedback_parts.append(
            f"PARTIAL: View only has {view_row_count} rows (expected >= 50 for multi-year data)."
        )
    else:
        subscores["view_data"] = 0
        feedback_parts.append(
            "FAIL: View has no data or could not be queried."
        )

    # ── Criterion 4: LAG() function working (10 pts) ──────────────────────────
    lag_works = result.get("lag_works", False)

    if lag_works:
        score += 10
        subscores["lag_works"] = 10
        feedback_parts.append(
            "PASS: PrevQuarterSales column has non-zero values, indicating LAG() is correctly implemented."
        )
    elif view_exists:
        subscores["lag_works"] = 0
        feedback_parts.append(
            "FAIL: PrevQuarterSales has no non-zero values. Check LAG() OVER (PARTITION BY SalesPersonID ORDER BY CalendarYear, CalendarQuarter)."
        )
    else:
        subscores["lag_works"] = 0
        feedback_parts.append("FAIL: LAG check skipped (view does not exist).")

    # ── Criterion 5: DENSE_RANK() starting at 1 (5 pts) ──────────────────────
    rank_starts_at_1 = result.get("rank_starts_at_1", False)

    if rank_starts_at_1:
        score += 5
        subscores["rank_starts_at_1"] = 5
        feedback_parts.append(
            "PASS: SalesRankInTerritory minimum is 1, indicating DENSE_RANK() is correctly implemented."
        )
    elif view_exists:
        subscores["rank_starts_at_1"] = 0
        feedback_parts.append(
            "FAIL: SalesRankInTerritory minimum is not 1. Check DENSE_RANK() OVER (PARTITION BY TerritoryName, CalendarYear ORDER BY QuarterlySales DESC)."
        )
    else:
        subscores["rank_starts_at_1"] = 0
        feedback_parts.append("FAIL: DENSE_RANK check skipped (view does not exist).")

    # ── Criterion 6: CSV file exists (15 pts) ─────────────────────────────────
    if csv_exists:
        score += 15
        subscores["csv_exists"] = 15
        feedback_parts.append(
            "PASS: CSV file exists at /home/ga/Documents/exports/top_sales_trends.csv."
        )
    else:
        subscores["csv_exists"] = 0
        feedback_parts.append(
            "FAIL: CSV file not found at /home/ga/Documents/exports/top_sales_trends.csv."
        )

    # ── Criterion 7: CSV has exactly 5 data rows (10 pts) ─────────────────────
    csv_row_count = result.get("csv_row_count", 0)
    csv_has_header = result.get("csv_has_header", False)

    if csv_exists and csv_row_count == 5:
        score += 10
        subscores["csv_rows"] = 10
        feedback_parts.append(
            "PASS: CSV has exactly 5 data rows (top 5 salespersons by average QoQ growth)."
        )
    elif csv_exists and csv_row_count > 0:
        score += 5
        subscores["csv_rows"] = 5
        feedback_parts.append(
            f"PARTIAL: CSV has {csv_row_count} data rows, but expected exactly 5."
        )
    elif csv_exists:
        subscores["csv_rows"] = 0
        feedback_parts.append(
            "FAIL: CSV file is empty or has no data rows."
        )
    else:
        subscores["csv_rows"] = 0
        feedback_parts.append("FAIL: CSV row count check skipped (file does not exist).")

    # ── Criterion 8: CSV data matches DB query (15 pts) ───────────────────────
    csv_db_match_count = result.get("csv_db_match_count", 0)

    if csv_db_match_count >= 3:
        score += 15
        subscores["csv_db_match"] = 15
        feedback_parts.append(
            f"PASS: {csv_db_match_count}/5 salesperson names in CSV match the database's "
            f"top performers by average QoQ growth (data integrity confirmed)."
        )
    elif csv_db_match_count >= 1:
        partial = int(csv_db_match_count / 5 * 15)
        score += partial
        subscores["csv_db_match"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {csv_db_match_count}/5 CSV names match the DB top performers. "
            f"Verify the ORDER BY AVG(QoQGrowthPct) DESC clause and that PrevQuarterSales > 0 filter is applied."
        )
    elif csv_exists and view_exists:
        subscores["csv_db_match"] = 0
        feedback_parts.append(
            "FAIL: CSV salesperson names do not match the expected top 5 by average QoQ growth. "
            "Check: SELECT TOP 5 ... ORDER BY AVG(QoQGrowthPct) DESC WHERE PrevQuarterSales > 0."
        )
    else:
        subscores["csv_db_match"] = 0
        feedback_parts.append("FAIL: CSV/DB cross-validation skipped (CSV or view missing).")

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
