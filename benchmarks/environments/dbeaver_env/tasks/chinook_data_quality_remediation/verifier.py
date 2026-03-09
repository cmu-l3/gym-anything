#!/usr/bin/env python3
"""
Verifier for chinook_data_quality_remediation task.

Scoring (100 points):
- DBeaver 'ChinookAudit' connection exists: 15 pts
- All orphaned invoice_items deleted (count = 0): 25 pts
- All NULL Rock track composers fixed (count = 0): 25 pts
- quality_audit.csv exists with 3 issue type rows: 20 pts
- CSV RecordsAffected values approximately match ground truth: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

AUDIT_CSV_PATH = "/home/ga/Documents/exports/quality_audit.csv"


def verify_chinook_data_quality_remediation(traj, env_info, task_info):
    """Verify data quality remediation task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/chinook_quality_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: DBeaver 'ChinookAudit' connection (15 pts) ---
    if result.get("chinook_audit_conn_found"):
        score += 15
        subscores["connection"] = 15
        feedback.append("ChinookAudit DBeaver connection found")
    else:
        subscores["connection"] = 0
        feedback.append("MISSING: DBeaver 'ChinookAudit' connection not found")

    # --- Criterion 2: Orphaned invoice_items fixed (25 pts) ---
    remaining_orphans = result.get("remaining_orphaned_items", -1)
    gt_orphans = result.get("gt_orphaned_items", 0)

    if remaining_orphans == 0:
        score += 25
        subscores["orphans_fixed"] = 25
        feedback.append(f"All orphaned invoice_items deleted (was {gt_orphans})")
    elif remaining_orphans > 0 and gt_orphans > 0:
        # Partial credit for reducing orphans
        pct_fixed = (gt_orphans - remaining_orphans) / gt_orphans
        partial = int(25 * pct_fixed)
        score += partial
        subscores["orphans_fixed"] = partial
        feedback.append(f"Partially fixed orphans: {remaining_orphans} remain of {gt_orphans} original")
    elif remaining_orphans == -1:
        subscores["orphans_fixed"] = 0
        feedback.append("Cannot check orphaned records (DB not accessible)")
    else:
        subscores["orphans_fixed"] = 0
        feedback.append(f"FAIL: {remaining_orphans} orphaned invoice_items remain")

    # --- Criterion 3: NULL Rock composers fixed (25 pts) ---
    remaining_null = result.get("remaining_null_rock_composers", -1)
    gt_null = result.get("gt_null_composers", 0)
    unknown_count = result.get("unknown_composer_count", 0)

    if remaining_null == 0 and unknown_count > 0:
        score += 25
        subscores["composers_fixed"] = 25
        feedback.append(f"All NULL Rock composers set to 'Unknown' ({unknown_count} records)")
    elif remaining_null == 0 and unknown_count == 0:
        # Fixed but using different method (e.g., different string)
        score += 15
        subscores["composers_fixed"] = 15
        feedback.append("NULL Rock composers fixed but 'Unknown' string not used")
    elif remaining_null > 0 and gt_null > 0:
        pct_fixed = (gt_null - remaining_null) / gt_null
        partial = int(25 * pct_fixed)
        score += partial
        subscores["composers_fixed"] = partial
        feedback.append(f"Partially fixed composers: {remaining_null} NULL remain of {gt_null}")
    elif remaining_null == -1:
        subscores["composers_fixed"] = 0
        feedback.append("Cannot check NULL composer count (DB not accessible)")
    else:
        subscores["composers_fixed"] = 0
        feedback.append(f"FAIL: {remaining_null} NULL Rock composers remain")

    # --- Criterion 4: Audit CSV exists with required rows (20 pts) ---
    if result.get("csv_exists"):
        row_count = result.get("csv_row_count", 0)
        has_orphan = result.get("csv_has_orphan_row", False)
        has_composer = result.get("csv_has_composer_row", False)
        has_email = result.get("csv_has_email_row", False)

        issue_rows_found = sum([has_orphan, has_composer, has_email])

        if issue_rows_found == 3 and row_count >= 3:
            score += 20
            subscores["audit_csv"] = 20
            feedback.append(f"Audit CSV has all 3 required issue type rows")
        elif issue_rows_found == 2:
            score += 12
            subscores["audit_csv"] = 12
            feedback.append(f"Audit CSV has 2/3 required issue types")
        elif issue_rows_found == 1 or row_count >= 1:
            score += 6
            subscores["audit_csv"] = 6
            feedback.append(f"Audit CSV exists with partial content ({issue_rows_found}/3 issue types)")
        else:
            score += 3
            subscores["audit_csv"] = 3
            feedback.append("Audit CSV exists but content not recognized")
    else:
        subscores["audit_csv"] = 0
        feedback.append(f"MISSING: quality_audit.csv not found at {AUDIT_CSV_PATH}")

    # --- Criterion 5: CSV counts match ground truth (15 pts) ---
    gt_orphans_val = result.get("gt_orphaned_items", 0)
    csv_orphan_reported = result.get("csv_orphan_count_reported", 0)

    if gt_orphans_val > 0 and csv_orphan_reported > 0:
        pct_diff = abs(csv_orphan_reported - gt_orphans_val) / gt_orphans_val
        if pct_diff <= 0.10:
            score += 15
            subscores["count_accuracy"] = 15
            feedback.append(f"CSV orphan count {csv_orphan_reported} matches GT {gt_orphans_val}")
        elif pct_diff <= 0.30:
            score += 8
            subscores["count_accuracy"] = 8
            feedback.append(f"CSV orphan count close to GT (diff {pct_diff*100:.0f}%)")
        else:
            subscores["count_accuracy"] = 0
            feedback.append(f"CSV orphan count {csv_orphan_reported} far from GT {gt_orphans_val}")
    elif result.get("csv_exists") and result.get("csv_row_count", 0) >= 3:
        # CSV has rows but we couldn't extract the count — partial credit
        score += 7
        subscores["count_accuracy"] = 7
        feedback.append("CSV has rows but count values could not be parsed")
    else:
        subscores["count_accuracy"] = 0
        feedback.append("CSV count data not available for comparison")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "remaining_orphans": result.get("remaining_orphaned_items"),
            "remaining_null_composers": result.get("remaining_null_rock_composers"),
            "gt_orphans": result.get("gt_orphaned_items"),
            "gt_null_composers": result.get("gt_null_composers")
        }
    }
