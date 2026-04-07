"""
Verifier for wac_inventory_ledger task.

Occupation: Cost Accountant (SOC 13-2011.01)
Context: Build a running weighted average cost inventory ledger from
         Production.TransactionHistory and a cost variance report view
         in AdventureWorks2022.
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_wac_inventory_ledger(traj, env_info, task_info):
    """
    Score the wac_inventory_ledger task.

    Expected objects in AdventureWorks2022:
    - Production.InventoryLedger table (9 columns)
    - Production.usp_BuildWACLedger stored procedure
    - Production.vw_CostVarianceReport view (6 columns)
    - CSV export at /home/ga/Documents/exports/cost_variance.csv
    """
    copy_from_env = env_info.get("copy_from_env")

    # ── Copy result JSON from VM ─────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/wac_result.json", tmp.name)
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

    # ── GATE: Wrong-target detection ─────────────────────────────────────────
    table_exists = result.get("table_exists", False)
    proc_exists = result.get("proc_exists", False)
    view_exists = result.get("view_exists", False)

    if not table_exists and not proc_exists and not view_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: None of the required objects were found in AdventureWorks2022 "
                "(Production.InventoryLedger, Production.usp_BuildWACLedger, "
                "Production.vw_CostVarianceReport). The agent may have worked on the wrong "
                "database or created no objects at all."
            ),
            "subscores": {"gate": 0},
        }

    # ── Criterion 1: Stored procedure exists (10 pts) ────────────────────────
    if proc_exists:
        score += 10
        subscores["stored_proc"] = 10
        feedback_parts.append("PASS: Stored procedure Production.usp_BuildWACLedger exists.")
    else:
        subscores["stored_proc"] = 0
        feedback_parts.append("FAIL: Stored procedure Production.usp_BuildWACLedger not found.")

    # ── Criterion 2: Table exists with required columns (15 pts) ─────────────
    if table_exists:
        score += 5
        subscores["table_exists"] = 5
        feedback_parts.append("PASS: Production.InventoryLedger table exists.")
    else:
        subscores["table_exists"] = 0
        feedback_parts.append("FAIL: Production.InventoryLedger table not found.")

    has_required_columns = result.get("has_required_columns", False)
    required_column_count = result.get("required_column_count", 0)
    columns_found = result.get("columns_found", "")

    if has_required_columns:
        score += 10
        subscores["table_columns"] = 10
        feedback_parts.append(
            "PASS: Table has all 9 required columns "
            "(TransactionID, ProductID, TransactionDate, TransactionType, "
            "Qty, UnitCost, RunningQty, RunningWAC, RunningTotalValue)."
        )
    elif table_exists and required_column_count > 0:
        partial = min(7, int(required_column_count / 9 * 10))
        score += partial
        subscores["table_columns"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {required_column_count}/9 required columns found. "
            f"Columns: {columns_found}"
        )
    else:
        subscores["table_columns"] = 0
        feedback_parts.append("FAIL: Table column check could not be performed.")

    # ── Criterion 3: Table populated with data (15 pts) ──────────────────────
    table_row_count = result.get("table_row_count", 0)
    distinct_products = result.get("distinct_products", 0)

    if table_exists and table_row_count >= 50000 and distinct_products >= 100:
        score += 15
        subscores["table_data"] = 15
        feedback_parts.append(
            f"PASS: Table has {table_row_count} rows covering {distinct_products} products."
        )
    elif table_exists and table_row_count >= 10000:
        score += 10
        subscores["table_data"] = 10
        feedback_parts.append(
            f"PARTIAL: Table has {table_row_count} rows ({distinct_products} products). "
            f"Expected 50K+ rows covering 100+ products from TransactionHistory."
        )
    elif table_exists and table_row_count > 0:
        score += 5
        subscores["table_data"] = 5
        feedback_parts.append(
            f"PARTIAL: Table has only {table_row_count} rows. "
            f"Did you process ALL products from Production.TransactionHistory?"
        )
    else:
        subscores["table_data"] = 0
        feedback_parts.append(
            "FAIL: Production.InventoryLedger has no data. "
            "Did you execute Production.usp_BuildWACLedger?"
        )

    # ── Criterion 4: No negative RunningQty (10 pts) ─────────────────────────
    negative_qty_count = result.get("negative_qty_count", -1)

    if negative_qty_count == 0:
        score += 10
        subscores["no_negative_qty"] = 10
        feedback_parts.append("PASS: No negative RunningQty values (zero-reset logic correct).")
    elif negative_qty_count > 0:
        subscores["no_negative_qty"] = 0
        feedback_parts.append(
            f"FAIL: Found {negative_qty_count} rows with negative RunningQty. "
            f"When RunningQty drops to zero or below, it must reset to zero."
        )
    else:
        subscores["no_negative_qty"] = 0
        feedback_parts.append("FAIL: Could not check RunningQty values.")

    # ── Criterion 5: WAC resets to 0 when qty = 0 (10 pts) ───────────────────
    zero_qty_nonzero_wac = result.get("zero_qty_nonzero_wac", -1)

    if zero_qty_nonzero_wac == 0:
        score += 10
        subscores["wac_reset"] = 10
        feedback_parts.append("PASS: RunningWAC correctly resets to 0 when RunningQty is 0.")
    elif zero_qty_nonzero_wac > 0:
        subscores["wac_reset"] = 0
        feedback_parts.append(
            f"FAIL: Found {zero_qty_nonzero_wac} rows where RunningQty=0 but RunningWAC!=0. "
            f"Both must reset to zero simultaneously."
        )
    else:
        subscores["wac_reset"] = 0
        feedback_parts.append("FAIL: Could not check WAC reset logic.")

    # ── Criterion 6: View exists with required columns (10 pts) ──────────────
    if view_exists:
        score += 5
        subscores["view_exists"] = 5
        feedback_parts.append("PASS: Production.vw_CostVarianceReport view exists.")
    else:
        subscores["view_exists"] = 0
        feedback_parts.append("FAIL: Production.vw_CostVarianceReport view not found.")

    view_has_required_columns = result.get("view_has_required_columns", False)
    view_required_column_count = result.get("view_required_column_count", 0)

    if view_has_required_columns:
        score += 5
        subscores["view_columns"] = 5
        feedback_parts.append(
            "PASS: View has required columns "
            "(ProductID, ProductName, FinalWAC, StandardCost, VariancePct, Flag)."
        )
    elif view_exists and view_required_column_count > 0:
        partial = min(3, int(view_required_column_count / 6 * 5))
        score += partial
        subscores["view_columns"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {view_required_column_count}/6 required view columns found."
        )
    else:
        subscores["view_columns"] = 0
        feedback_parts.append("FAIL: View column check could not be performed.")

    # ── Criterion 7: View has data (10 pts) ──────────────────────────────────
    view_row_count = result.get("view_row_count", 0)
    investigate_count = result.get("investigate_count", 0)

    if view_exists and view_row_count >= 50:
        score += 10
        subscores["view_data"] = 10
        feedback_parts.append(
            f"PASS: View returns {view_row_count} rows "
            f"({investigate_count} flagged INVESTIGATE)."
        )
    elif view_exists and view_row_count > 0:
        score += 5
        subscores["view_data"] = 5
        feedback_parts.append(
            f"PARTIAL: View returns {view_row_count} rows (expected 50+ for "
            f"products with transactions)."
        )
    else:
        subscores["view_data"] = 0
        feedback_parts.append("FAIL: View returns no data.")

    # ── Criterion 8: CSV export (20 pts) ─────────────────────────────────────
    csv_exists = result.get("csv_exists", False)
    csv_rows = result.get("csv_rows", 0)
    csv_header = result.get("csv_header", "")
    csv_created_during_task = result.get("csv_created_during_task", False)

    if csv_exists:
        score += 5
        subscores["csv_exists"] = 5
        feedback_parts.append("PASS: CSV file exists at expected path.")
    else:
        subscores["csv_exists"] = 0
        feedback_parts.append(
            "FAIL: CSV file not found at /home/ga/Documents/exports/cost_variance.csv."
        )

    if csv_exists and csv_created_during_task:
        score += 5
        subscores["csv_created_during_task"] = 5
        feedback_parts.append("PASS: CSV was created during this task session.")
    elif csv_exists:
        subscores["csv_created_during_task"] = 0
        feedback_parts.append("FAIL: CSV exists but was not created during this task session.")
    else:
        subscores["csv_created_during_task"] = 0

    if csv_exists and csv_rows >= 2:
        score += 5
        subscores["csv_has_data"] = 5
        feedback_parts.append(f"PASS: CSV has {csv_rows - 1} data rows.")
    elif csv_exists:
        subscores["csv_has_data"] = 0
        feedback_parts.append("FAIL: CSV file is empty or has only a header.")
    else:
        subscores["csv_has_data"] = 0

    csv_header_lower = csv_header.lower()
    if csv_exists and "productid" in csv_header_lower and "variance" in csv_header_lower:
        score += 5
        subscores["csv_header"] = 5
        feedback_parts.append("PASS: CSV header contains expected columns.")
    elif csv_exists:
        subscores["csv_header"] = 0
        feedback_parts.append(f"FAIL: CSV header missing expected columns: {csv_header}")
    else:
        subscores["csv_header"] = 0

    # ── Final verdict ────────────────────────────────────────────────────────
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
