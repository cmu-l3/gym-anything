"""
Verifier for product_bom_recursive_costing task.

Occupation: Cost Engineer / Industrial Engineer (SOC 17-2112.00)
Context: Build a recursive BOM hierarchy view and lifecycle cost reporting system
         in AdventureWorks2022 using recursive CTEs, aggregations, and stored procedures.
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_product_bom_recursive_costing(traj, env_info, task_info):
    """
    Score the product_bom_recursive_costing task.

    Expected objects in AdventureWorks2022:
    - dbo.vw_ProductBOMHierarchy view (7 columns, recursive CTE)
    - Production.LifecycleCostSummary table (8 columns, non-clustered index)
    - dbo.usp_GenerateBOMCostReport stored procedure
    - Production.LifecycleCostSummary populated with data
    """
    copy_from_env = env_info.get("copy_from_env")

    # ── Copy result JSON from VM ───────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/bom_cost_result.json", tmp.name)
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
    table_exists = result.get("table_exists", False)
    proc_exists = result.get("proc_exists", False)

    if not view_exists and not table_exists and not proc_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: None of the required objects were found in AdventureWorks2022 "
                "(dbo.vw_ProductBOMHierarchy, Production.LifecycleCostSummary, "
                "dbo.usp_GenerateBOMCostReport). The agent may have worked on the wrong "
                "database or created no objects at all."
            ),
            "subscores": {"gate": 0},
        }

    # ── Criterion 1: Recursive view exists (15 pts) ───────────────────────────
    if view_exists:
        score += 15
        subscores["view_exists"] = 15
        feedback_parts.append("PASS: View dbo.vw_ProductBOMHierarchy exists in AdventureWorks2022.")
    else:
        subscores["view_exists"] = 0
        feedback_parts.append("FAIL: View dbo.vw_ProductBOMHierarchy not found in AdventureWorks2022.")

    # ── Criterion 2: View has required columns (15 pts) ───────────────────────
    has_required_columns = result.get("has_required_columns", False)
    required_column_count = result.get("required_column_count", 0)
    columns_found = result.get("columns_found", "")

    if has_required_columns:
        score += 15
        subscores["view_columns"] = 15
        feedback_parts.append(
            "PASS: View has required columns (AssemblyProductID, AssemblyName, ComponentID, "
            "ComponentName, BOMLevel, PerAssemblyQty, UnitMeasureCode)."
        )
    elif view_exists and required_column_count > 0:
        partial = min(10, int(required_column_count / 7 * 15))
        score += partial
        subscores["view_columns"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {required_column_count}/7 required columns found in view. "
            f"Columns: {columns_found}"
        )
    else:
        subscores["view_columns"] = 0
        feedback_parts.append(
            "FAIL: Required columns check could not be performed (view missing or no columns found)."
        )

    # ── Criterion 3: View has data and uses real recursion (15 pts) ───────────
    view_row_count = result.get("view_row_count", 0)
    has_recursion = result.get("has_recursion", False)

    if view_exists and has_recursion and view_row_count >= 10:
        score += 15
        subscores["recursion"] = 15
        feedback_parts.append(
            f"PASS: View contains {view_row_count} BOM rows with multi-level recursion "
            f"(BOMLevel > 1 rows exist, confirming recursive CTE is functional)."
        )
    elif view_exists and view_row_count >= 10:
        score += 8
        subscores["recursion"] = 8
        feedback_parts.append(
            f"PARTIAL: View has {view_row_count} rows but no multi-level recursion detected "
            f"(all BOMLevel = 1). Check recursive CTE member joins back to BillOfMaterials."
        )
    elif view_exists and view_row_count > 0:
        score += 5
        subscores["recursion"] = 5
        feedback_parts.append(
            f"PARTIAL: View has {view_row_count} rows but fewer than expected "
            f"(expected >= 10 for AdventureWorks BOM data)."
        )
    else:
        subscores["recursion"] = 0
        feedback_parts.append("FAIL: View has no data or does not exist.")

    # ── Criterion 4: Production.LifecycleCostSummary table exists (10 pts) ────
    if table_exists:
        score += 10
        subscores["table_exists"] = 10
        feedback_parts.append("PASS: Production.LifecycleCostSummary table exists.")
    else:
        subscores["table_exists"] = 0
        feedback_parts.append("FAIL: Production.LifecycleCostSummary table not found.")

    # ── Criterion 5: Table has required columns (10 pts) ──────────────────────
    has_table_columns = result.get("has_table_columns", False)
    table_column_count = result.get("table_column_count", 0)
    table_columns_found = result.get("table_columns_found", "")

    if has_table_columns:
        score += 10
        subscores["table_columns"] = 10
        feedback_parts.append(
            "PASS: Production.LifecycleCostSummary has required columns "
            "(AssemblyProductID, AssemblyName, TotalBOMComponents, MaxBOMDepth, "
            "DirectMaterialCost, TotalMaterialCost)."
        )
    elif table_exists and table_column_count > 0:
        partial = min(7, int(table_column_count / 6 * 10))
        score += partial
        subscores["table_columns"] = partial
        feedback_parts.append(
            f"PARTIAL: Only {table_column_count} columns found in table. "
            f"Columns: {table_columns_found}"
        )
    else:
        subscores["table_columns"] = 0
        feedback_parts.append(
            "FAIL: Table column check could not be performed (table missing or no columns)."
        )

    # ── Criterion 6: Table is populated with cost data (15 pts) ──────────────
    table_row_count = result.get("table_row_count", 0)
    has_cost_data = result.get("has_cost_data", False)

    if table_exists and has_cost_data and table_row_count >= 5:
        score += 15
        subscores["table_data"] = 15
        feedback_parts.append(
            f"PASS: Production.LifecycleCostSummary has {table_row_count} rows with "
            f"non-zero TotalMaterialCost values (stored procedure executed successfully)."
        )
    elif table_exists and table_row_count >= 5:
        score += 8
        subscores["table_data"] = 8
        feedback_parts.append(
            f"PARTIAL: Table has {table_row_count} rows but TotalMaterialCost is zero for all. "
            f"Check the cost calculation joins Production.Product for StandardCost."
        )
    elif table_exists and table_row_count > 0:
        score += 5
        subscores["table_data"] = 5
        feedback_parts.append(
            f"PARTIAL: Table has only {table_row_count} rows (expected >= 5 for AdventureWorks assemblies). "
            f"Did you EXEC dbo.usp_GenerateBOMCostReport?"
        )
    else:
        subscores["table_data"] = 0
        feedback_parts.append(
            "FAIL: Production.LifecycleCostSummary has no data. "
            "Did you execute EXEC dbo.usp_GenerateBOMCostReport?"
        )

    # ── Criterion 7: Non-clustered index exists (5 pts) ───────────────────────
    index_exists = result.get("index_exists", False)

    if index_exists:
        score += 5
        subscores["index"] = 5
        feedback_parts.append(
            "PASS: Non-clustered index on Production.LifecycleCostSummary(AssemblyProductID) exists."
        )
    elif table_exists:
        subscores["index"] = 0
        feedback_parts.append(
            "FAIL: Non-clustered index on AssemblyProductID not found. "
            "Use: CREATE NONCLUSTERED INDEX IX_LifecycleCost_AssemblyProductID "
            "ON Production.LifecycleCostSummary (AssemblyProductID)."
        )
    else:
        subscores["index"] = 0
        feedback_parts.append("FAIL: Index check skipped (table does not exist).")

    # ── Criterion 8: Stored procedure exists (15 pts) ─────────────────────────
    if proc_exists:
        score += 15
        subscores["stored_proc"] = 15
        feedback_parts.append("PASS: Stored procedure dbo.usp_GenerateBOMCostReport exists.")
    else:
        subscores["stored_proc"] = 0
        feedback_parts.append("FAIL: Stored procedure dbo.usp_GenerateBOMCostReport not found.")

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
