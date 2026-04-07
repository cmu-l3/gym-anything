#!/usr/bin/env python3
"""
Verifier for chinook_revenue_reconciliation task.

Scoring (100 points):
- DBeaver 'LedgerAudit' connection exists:                  5 pts
- Duplicates removed (invoice_items count = original):     20 pts
- Credit memo removed (no negative invoices):              10 pts
- Q4 2013 invoice totals correct (Total = SUM(items)):     20 pts
- All months reconcile (GL matches actual revenue):        20 pts
- correction_log table exists with entries:                10 pts
- CSV exported at correct path:                            10 pts
- SQL script saved at correct path:                         5 pts

Pass threshold: 80 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_chinook_revenue_reconciliation(traj, env_info, task_info):
    """Verify revenue reconciliation task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Read the export result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/reconciliation_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}

    # Read ground truth
    gt = {}
    try:
        tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_gt.close()
        try:
            copy_from_env("/tmp/reconciliation_ground_truth.json", tmp_gt.name)
            with open(tmp_gt.name) as f:
                gt = json.load(f)
        finally:
            os.unlink(tmp_gt.name)
    except Exception as e:
        logger.warning(f"Could not read ground truth: {e}")

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: DBeaver connection (5 pts) ---
    if result.get("connection_found"):
        score += 5
        subscores["connection"] = 5
        feedback.append("LedgerAudit connection found")
    else:
        subscores["connection"] = 0
        feedback.append("MISSING: DBeaver 'LedgerAudit' connection not found")

    # --- Criterion 2: Duplicates removed (20 pts) ---
    expected_count = gt.get("original_invoice_item_count", 2240)
    actual_count = result.get("invoice_items_count", -1)

    if actual_count == expected_count:
        score += 20
        subscores["duplicates_removed"] = 20
        feedback.append(f"All duplicates removed (count={actual_count})")
    elif 0 < actual_count < expected_count:
        # Removed too many (deleted originals too)
        subscores["duplicates_removed"] = 5
        score += 5
        feedback.append(f"Over-deleted: {actual_count} items remain, expected {expected_count}")
    elif actual_count > expected_count:
        dup_count = gt.get("duplicate_count", 18)
        removed = (expected_count + dup_count) - actual_count
        if removed > 0:
            partial = min(15, int(20 * removed / dup_count))
            score += partial
            subscores["duplicates_removed"] = partial
            feedback.append(f"Partially removed: {removed}/{dup_count} duplicates")
        else:
            subscores["duplicates_removed"] = 0
            feedback.append(f"Duplicates not removed: {actual_count} items, expected {expected_count}")
    else:
        subscores["duplicates_removed"] = 0
        feedback.append(f"Cannot verify invoice_items count (got {actual_count})")

    # --- Criterion 3: Credit memo removed (10 pts) ---
    neg_count = result.get("negative_invoices_count", -1)
    if neg_count == 0:
        score += 10
        subscores["credit_memo_removed"] = 10
        feedback.append("Credit memo removed (no negative invoices)")
    elif neg_count == -1:
        subscores["credit_memo_removed"] = 0
        feedback.append("Cannot verify negative invoice count")
    else:
        subscores["credit_memo_removed"] = 0
        feedback.append(f"Credit memo not removed: {neg_count} negative invoice(s) remain")

    # --- Criterion 4: Q4 2013 invoice totals correct (20 pts) ---
    q4_mismatches = result.get("q4_total_mismatches", -1)
    if q4_mismatches == 0:
        score += 20
        subscores["q4_totals_correct"] = 20
        feedback.append("All Q4 2013 invoice totals match line item sums")
    elif q4_mismatches > 0:
        affected_count = len(gt.get("affected_invoice_ids", []))
        if affected_count > 0:
            fixed = affected_count - q4_mismatches
            partial = max(0, min(15, int(20 * fixed / affected_count)))
            score += partial
            subscores["q4_totals_correct"] = partial
            feedback.append(f"Q4 totals partially fixed: {q4_mismatches} still mismatched")
        else:
            subscores["q4_totals_correct"] = 0
            feedback.append(f"Q4 invoice totals not corrected ({q4_mismatches} mismatches)")
    else:
        subscores["q4_totals_correct"] = 0
        feedback.append("Cannot verify Q4 invoice totals")

    # --- Criterion 5: All months reconcile (20 pts) ---
    discrepant_count = result.get("discrepant_month_count", -1)
    if discrepant_count == 0:
        score += 20
        subscores["months_reconciled"] = 20
        feedback.append("All months reconcile with general ledger")
    elif discrepant_count > 0:
        # Partial credit: originally 3 months were off
        original_discrepant = 3
        fixed = max(0, original_discrepant - discrepant_count)
        partial = int(20 * fixed / original_discrepant)
        score += partial
        subscores["months_reconciled"] = partial
        discrepant_list = result.get("discrepant_months", "")
        feedback.append(f"{discrepant_count} month(s) still discrepant: {discrepant_list}")
    else:
        subscores["months_reconciled"] = 0
        feedback.append("Cannot verify monthly reconciliation")

    # --- Criterion 6: correction_log table (10 pts) ---
    if result.get("correction_log_exists"):
        rows = result.get("correction_log_rows", 0)
        if rows >= 3:
            score += 10
            subscores["correction_log"] = 10
            feedback.append(f"correction_log table has {rows} entries")
        elif rows >= 1:
            score += 6
            subscores["correction_log"] = 6
            feedback.append(f"correction_log exists but only {rows} entries (expected >= 3)")
        else:
            score += 3
            subscores["correction_log"] = 3
            feedback.append("correction_log table exists but is empty")
    else:
        subscores["correction_log"] = 0
        feedback.append("MISSING: correction_log table not found")

    # --- Criterion 7: CSV exported (10 pts) ---
    csv_info = result.get("csv_export", {})
    if csv_info.get("exists") and csv_info.get("created_during_task"):
        if csv_info.get("row_count", 0) >= 2:
            score += 10
            subscores["csv_exported"] = 10
            feedback.append(f"CSV exported ({csv_info['row_count']} lines)")
        else:
            score += 5
            subscores["csv_exported"] = 5
            feedback.append("CSV exists but appears empty or header-only")
    elif csv_info.get("exists"):
        score += 3
        subscores["csv_exported"] = 3
        feedback.append("CSV exists but may not have been created during task")
    else:
        subscores["csv_exported"] = 0
        feedback.append("MISSING: correction_report.csv not found")

    # --- Criterion 8: SQL script saved (5 pts) ---
    script_info = result.get("sql_script", {})
    if script_info.get("exists") and script_info.get("size_bytes", 0) > 50:
        score += 5
        subscores["sql_script"] = 5
        feedback.append("SQL script saved")
    elif script_info.get("exists"):
        score += 2
        subscores["sql_script"] = 2
        feedback.append("SQL script exists but appears very small")
    else:
        subscores["sql_script"] = 0
        feedback.append("MISSING: reconciliation.sql not found")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "invoice_items_count": result.get("invoice_items_count"),
            "expected_items": gt.get("original_invoice_item_count"),
            "negative_invoices": result.get("negative_invoices_count"),
            "discrepant_months": result.get("discrepant_month_count"),
            "q4_mismatches": result.get("q4_total_mismatches"),
            "correction_log_rows": result.get("correction_log_rows")
        }
    }
