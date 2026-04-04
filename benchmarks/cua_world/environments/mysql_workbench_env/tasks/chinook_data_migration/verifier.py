#!/usr/bin/env python3
"""Verifier for chinook_data_migration task.

A Software Developer task: fix data integrity issues in the Chinook music store DB,
create a reporting view, add an index, and export results.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_chinook_data_migration(traj, env_info, task_info):
    """
    Verify chinook data migration task completion.

    Scoring (100 points):
    - All NULL BillingAddress records fixed (0 remaining): 25 pts
    - All wrong UnitPrice InvoiceLines fixed (0 remaining): 25 pts
    - v_sales_by_genre view created with >= 10 genres: 25 pts
    - idx_invoiceline_trackid index created: 15 pts
    - CSV export with >= 10 rows created after task start: 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/chinook_migration_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []

    # Criterion 1: NULL BillingAddress fixed (25 pts)
    null_remaining = result.get('null_billing_remaining', 99)
    null_initial = result.get('null_billing_initial', 15)
    if null_remaining == 0:
        score += 25
        feedback_parts.append(f"All {null_initial} NULL BillingAddress records fixed (25/25)")
    elif null_remaining < null_initial:
        partial = int(25 * (null_initial - null_remaining) / max(null_initial, 1))
        score += partial
        feedback_parts.append(f"Partially fixed NULL BillingAddress: {null_remaining} remaining ({partial}/25)")
    else:
        feedback_parts.append(f"NULL BillingAddress NOT fixed: {null_remaining} remaining (0/25)")

    # Criterion 2: Wrong UnitPrice InvoiceLines fixed (25 pts)
    wrong_remaining = result.get('wrong_unitprice_remaining', 99)
    wrong_initial = result.get('wrong_unitprice_initial', 3)
    if wrong_remaining == 0:
        score += 25
        feedback_parts.append(f"All {wrong_initial} wrong UnitPrice records fixed (25/25)")
    elif wrong_remaining < wrong_initial:
        partial = int(25 * (wrong_initial - wrong_remaining) / max(wrong_initial, 1))
        score += partial
        feedback_parts.append(f"Partially fixed UnitPrice: {wrong_remaining} remaining ({partial}/25)")
    else:
        feedback_parts.append(f"Wrong UnitPrice NOT fixed: {wrong_remaining} remaining (0/25)")

    # Criterion 3: v_sales_by_genre view created with meaningful content (25 pts)
    if result.get('view_exists', 0) > 0:
        view_rows = result.get('view_row_count', 0)
        if view_rows >= 10:
            score += 25
            feedback_parts.append(f"v_sales_by_genre view created with {view_rows} genres (25/25)")
        elif view_rows > 0:
            score += 10
            feedback_parts.append(f"v_sales_by_genre view created but only {view_rows} genres (10/25)")
        else:
            score += 5
            feedback_parts.append("v_sales_by_genre view exists but appears empty (5/25)")
    else:
        feedback_parts.append("v_sales_by_genre view NOT created (0/25)")

    # Criterion 4: idx_invoiceline_trackid index created (15 pts)
    if result.get('index_exists', 0) > 0:
        score += 15
        feedback_parts.append("idx_invoiceline_trackid index created (15/15)")
    else:
        feedback_parts.append("idx_invoiceline_trackid index NOT created (0/15)")

    # Criterion 5: CSV export created after task start (10 pts)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)

    if csv_exists and int(csv_mtime) > task_start and csv_rows >= 10:
        score += 10
        feedback_parts.append(f"CSV export created with {csv_rows} genre rows (10/10)")
    elif csv_exists and csv_rows >= 10:
        score += 5
        feedback_parts.append(f"CSV has {csv_rows} rows but may be pre-existing (5/10)")
    else:
        feedback_parts.append(f"CSV export missing or insufficient ({csv_rows} rows) (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
