#!/usr/bin/env python3
"""Verifier for sakila_performance_optimization task.

A Computer Systems Analyst / DBA task: diagnose missing indexes, restore them,
create a reporting view and stored procedure, export results.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_sakila_performance_optimization(traj, env_info, task_info):
    """
    Verify sakila performance optimization task completion.

    Scoring (100 points):
    - rental.customer_id index restored: 20 pts
    - payment.rental_id index restored: 20 pts
    - inventory.film_id index restored: 10 pts
    - v_monthly_revenue view created: 20 pts
    - sp_monthly_revenue procedure created: 20 pts
    - CSV export with >= 12 rows created after task start: 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/perf_opt_result.json", tmp.name)
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

    # Criterion 1: rental.customer_id index restored (20 pts)
    if result.get('idx_rental_customer_restored', 0) > 0:
        score += 20
        feedback_parts.append("rental customer_id index restored (20/20)")
    else:
        feedback_parts.append("rental customer_id index NOT restored (0/20)")

    # Criterion 2: payment.rental_id index restored (20 pts)
    if result.get('idx_payment_rental_restored', 0) > 0:
        score += 20
        feedback_parts.append("payment rental_id index restored (20/20)")
    else:
        feedback_parts.append("payment rental_id index NOT restored (0/20)")

    # Criterion 3: inventory.film_id index restored (10 pts)
    if result.get('idx_inventory_film_restored', 0) > 0:
        score += 10
        feedback_parts.append("inventory film_id index restored (10/10)")
    else:
        feedback_parts.append("inventory film_id index NOT restored (0/10)")

    # Criterion 4: v_monthly_revenue view created with meaningful columns (20 pts)
    if result.get('view_exists', 0) > 0:
        col_ok = (result.get('view_has_year_col', 0) and
                  result.get('view_has_month_col', 0) and
                  result.get('view_has_revenue_col', 0))
        if col_ok:
            score += 20
            feedback_parts.append("v_monthly_revenue view created with year/month/revenue columns (20/20)")
        else:
            score += 10
            feedback_parts.append("v_monthly_revenue view exists but missing expected columns (10/20)")
    else:
        feedback_parts.append("v_monthly_revenue view NOT created (0/20)")

    # Criterion 5: sp_monthly_revenue procedure created (20 pts)
    if result.get('proc_exists', 0) > 0:
        score += 20
        feedback_parts.append("sp_monthly_revenue procedure created (20/20)")
    else:
        feedback_parts.append("sp_monthly_revenue procedure NOT created (0/20)")

    # Criterion 6: CSV export created after task start with >= 12 rows (10 pts)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)

    if csv_exists and int(csv_mtime) > task_start and csv_rows >= 12:
        score += 10
        feedback_parts.append(f"CSV export created with {csv_rows} rows (10/10)")
    elif csv_exists and csv_rows >= 12:
        score += 5
        feedback_parts.append(f"CSV has {csv_rows} rows but may be pre-existing (5/10)")
    else:
        feedback_parts.append(f"CSV export missing or has only {csv_rows} rows (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
