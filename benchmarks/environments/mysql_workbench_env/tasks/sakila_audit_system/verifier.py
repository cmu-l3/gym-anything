#!/usr/bin/env python3
"""Verifier for sakila_audit_system task.

A Software Developer task: implement a database trigger (AFTER UPDATE), a stored
procedure with tier logic, test the trigger with real UPDATE statements, call the
procedure, and export the results.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_sakila_audit_system(traj, env_info, task_info):
    """
    Verify sakila audit system task completion.

    Scoring (100 points):
    - tr_customer_audit trigger created (AFTER UPDATE on customer): 25 pts
    - sp_calculate_loyalty_tiers procedure created: 20 pts
    - customer_audit_log has >= 5 entries from >= 5 distinct customers: 20 pts
    - customer_loyalty populated with all 3 tiers present and >= 500 rows: 25 pts
    - CSV export of customer_loyalty with >= 500 rows: 10 pts

    Pass threshold: 60 points

    GATE: If audit_log has 0 entries AND loyalty has 0 entries AND CSV missing,
    do-nothing scenario → score=0.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/audit_system_result.json", tmp.name)
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

    # Criterion 1: tr_customer_audit trigger created as AFTER UPDATE (25 pts)
    trigger_exists = result.get('trigger_exists', 0)
    is_after_update = result.get('trigger_is_after_update', 0)

    if trigger_exists and is_after_update:
        score += 25
        feedback_parts.append("tr_customer_audit AFTER UPDATE trigger created (25/25)")
    elif trigger_exists:
        score += 10
        feedback_parts.append("tr_customer_audit trigger exists but wrong timing/event (10/25)")
    else:
        feedback_parts.append("tr_customer_audit trigger NOT created (0/25)")

    # Criterion 2: sp_calculate_loyalty_tiers procedure created (20 pts)
    if result.get('proc_exists', 0):
        score += 20
        feedback_parts.append("sp_calculate_loyalty_tiers procedure created (20/20)")
    else:
        feedback_parts.append("sp_calculate_loyalty_tiers procedure NOT created (0/20)")

    # Criterion 3: Trigger was tested (audit_log has >= 5 entries from >= 5 distinct customers) (20 pts)
    audit_count = result.get('audit_log_count', 0)
    distinct_customers = result.get('audit_distinct_customers', 0)
    has_emails = result.get('audit_has_emails', 0)

    if audit_count >= 5 and distinct_customers >= 5:
        if has_emails:
            score += 20
            feedback_parts.append(f"Trigger tested: {audit_count} audit log entries across {distinct_customers} customers with emails (20/20)")
        else:
            score += 15
            feedback_parts.append(f"Trigger fired {audit_count} times ({distinct_customers} customers) but email fields may be missing (15/20)")
    elif audit_count >= 1:
        score += 8
        feedback_parts.append(f"Trigger partially tested: only {audit_count} entries from {distinct_customers} distinct customers (8/20)")
    else:
        feedback_parts.append("Trigger NOT tested: audit_log is empty (0/20)")

    # Criterion 4: customer_loyalty populated with correct tier structure (25 pts)
    loyalty_count = result.get('loyalty_count', 0)
    bronze = result.get('bronze_count', 0)
    silver = result.get('silver_count', 0)
    gold = result.get('gold_count', 0)
    all_tiers_present = bronze > 0 and silver > 0 and gold > 0

    if loyalty_count >= 500 and all_tiers_present:
        score += 25
        feedback_parts.append(f"customer_loyalty populated: {loyalty_count} rows, all tiers present (B={bronze}/S={silver}/G={gold}) (25/25)")
    elif loyalty_count >= 100 and all_tiers_present:
        score += 15
        feedback_parts.append(f"customer_loyalty: {loyalty_count} rows, all tiers present (15/25)")
    elif loyalty_count >= 1:
        score += 8
        feedback_parts.append(f"customer_loyalty partially populated: {loyalty_count} rows, tiers: B={bronze}/S={silver}/G={gold} (8/25)")
    else:
        feedback_parts.append("customer_loyalty is empty — sp_calculate_loyalty_tiers not called or failed (0/25)")

    # Criterion 5: CSV export with >= 500 rows created after task start (10 pts)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)

    if csv_exists and int(csv_mtime) > task_start and csv_rows >= 500:
        score += 10
        feedback_parts.append(f"CSV export created with {csv_rows} loyalty rows (10/10)")
    elif csv_exists and csv_rows >= 100:
        score += 5
        feedback_parts.append(f"CSV has {csv_rows} rows (5/10)")
    else:
        feedback_parts.append(f"CSV export missing or insufficient ({csv_rows} rows) (0/10)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
