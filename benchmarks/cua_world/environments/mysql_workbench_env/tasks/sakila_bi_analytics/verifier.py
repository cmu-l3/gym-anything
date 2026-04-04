#!/usr/bin/env python3
"""Verifier for sakila_bi_analytics task.

A BI Analyst task: create reporting views, set up a read-only user with
appropriate privileges, and export analytics data.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_sakila_bi_analytics(traj, env_info, task_info):
    """
    Verify Sakila BI analytics task completion.

    Scoring (100 points):
    - v_film_revenue_by_store view with correct columns: 20 pts
    - v_customer_lifetime_value view with correct columns and >= 500 rows: 20 pts
    - reporter@localhost user created: 20 pts
    - reporter has SELECT on v_film_revenue_by_store: 15 pts
    - reporter has SELECT on v_customer_lifetime_value: 15 pts
    - CSV export with >= 500 rows created after task start: 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/bi_analytics_result.json", tmp.name)
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

    # Criterion 1: v_film_revenue_by_store view with meaningful columns (20 pts)
    if result.get('view1_exists', 0) > 0:
        col_score = sum([
            result.get('view1_has_film_id', 0),
            result.get('view1_has_store_id', 0),
            result.get('view1_has_rental_count', 0),
            result.get('view1_has_revenue', 0),
        ])
        if col_score >= 3:
            score += 20
            feedback_parts.append(f"v_film_revenue_by_store view with {col_score}/4 required columns (20/20)")
        elif col_score >= 2:
            score += 10
            feedback_parts.append(f"v_film_revenue_by_store view exists but only {col_score}/4 required columns (10/20)")
        else:
            score += 5
            feedback_parts.append(f"v_film_revenue_by_store exists but missing most required columns (5/20)")
    else:
        feedback_parts.append("v_film_revenue_by_store view NOT created (0/20)")

    # Criterion 2: v_customer_lifetime_value view with correct columns and data (20 pts)
    if result.get('view2_exists', 0) > 0:
        col_score2 = sum([
            result.get('view2_has_customer_id', 0),
            result.get('view2_has_name', 0),
            result.get('view2_has_total', 0),
        ])
        row_count = result.get('view2_row_count', 0)
        if col_score2 >= 2 and row_count >= 500:
            score += 20
            feedback_parts.append(f"v_customer_lifetime_value view with {col_score2}/3 cols and {row_count} rows (20/20)")
        elif col_score2 >= 2 or row_count >= 100:
            score += 10
            feedback_parts.append(f"v_customer_lifetime_value view exists (cols={col_score2}/3, rows={row_count}) (10/20)")
        else:
            score += 5
            feedback_parts.append(f"v_customer_lifetime_value exists but insufficient content (5/20)")
    else:
        feedback_parts.append("v_customer_lifetime_value view NOT created (0/20)")

    # Criterion 3: reporter@localhost user created (20 pts)
    if result.get('user_exists', 0) > 0:
        score += 20
        feedback_parts.append("reporter@localhost user created (20/20)")
    else:
        feedback_parts.append("reporter@localhost user NOT created (0/20)")

    # Criterion 4: reporter has SELECT on v_film_revenue_by_store (15 pts)
    if result.get('reporter_has_view1_priv', 0) > 0:
        score += 15
        feedback_parts.append("reporter has SELECT on v_film_revenue_by_store (15/15)")
    else:
        feedback_parts.append("reporter does NOT have SELECT on v_film_revenue_by_store (0/15)")

    # Criterion 5: reporter has SELECT on v_customer_lifetime_value (15 pts)
    if result.get('reporter_has_view2_priv', 0) > 0:
        score += 15
        feedback_parts.append("reporter has SELECT on v_customer_lifetime_value (15/15)")
    else:
        feedback_parts.append("reporter does NOT have SELECT on v_customer_lifetime_value (0/15)")

    # Criterion 6: CSV export (10 pts)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)

    if csv_exists and int(csv_mtime) > task_start and csv_rows >= 500:
        score += 10
        feedback_parts.append(f"CSV export created with {csv_rows} customer rows (10/10)")
    elif csv_exists and csv_rows >= 100:
        score += 5
        feedback_parts.append(f"CSV exists with {csv_rows} rows but may be pre-existing or sparse (5/10)")
    else:
        feedback_parts.append(f"CSV export missing or has too few rows ({csv_rows}) (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
