#!/usr/bin/env python3
"""Verifier for sakila_pareto_revenue_analysis task.

A Business Intelligence Analyst task: Pareto (80/20) analysis using Window Functions.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_sakila_pareto_revenue_analysis(traj, env_info, task_info):
    """
    Verify Sakila Pareto analysis task completion.

    Scoring (100 points):
    - View v_customer_ltv exists: 20 pts
    - View v_pareto_revenue exists: 30 pts
    - Percentage Logic Correct (View query check): 20 pts
    - CSV Export exists and created during task: 10 pts
    - CSV Content (correct rows/cutoff): 20 pts

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/pareto_result.json", tmp.name)
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

    # 1. View v_customer_ltv (20 pts)
    if result.get('ltv_view_exists', 0) > 0:
        score += 20
        feedback_parts.append("v_customer_ltv created (20/20)")
    else:
        feedback_parts.append("v_customer_ltv missing (0/20)")

    # 2. View v_pareto_revenue (30 pts)
    if result.get('pareto_view_exists', 0) > 0:
        if result.get('view_columns_ok', False):
            score += 30
            feedback_parts.append("v_pareto_revenue created with correct columns (30/30)")
        else:
            score += 15
            feedback_parts.append("v_pareto_revenue created but missing required columns (15/30)")
    else:
        feedback_parts.append("v_pareto_revenue missing (0/30)")

    # 3. Logic Check (20 pts)
    # We checked max_pct (~100) and running total size in export script
    logic_ok = result.get('pct_calc_logic_ok', False) and result.get('running_total_logic_ok', False)
    if logic_ok:
        score += 20
        feedback_parts.append("Window functions logic correct (20/20)")
    elif result.get('pareto_view_exists', 0) > 0:
        feedback_parts.append("Window functions logic incorrect (cumulative pct not ~100%) (0/20)")

    # 4. CSV Existence (10 pts)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    csv_exists = result.get('csv_exists', False)
    
    if csv_exists and int(csv_mtime) > task_start:
        score += 10
        feedback_parts.append("CSV export file created (10/10)")
    elif csv_exists:
        score += 5
        feedback_parts.append("CSV exists but old timestamp (5/10)")
    else:
        feedback_parts.append("CSV export missing (0/10)")

    # 5. CSV Content/Cutoff (20 pts)
    # Expect roughly 130-150 rows for 80% of revenue in Sakila
    csv_rows = result.get('csv_rows', 0)
    csv_valid_cutoff = result.get('csv_valid_cutoff', False)
    
    if csv_rows >= 100 and csv_rows <= 160 and csv_valid_cutoff:
        score += 20
        feedback_parts.append(f"CSV content valid (~80% cutoff, {csv_rows} rows) (20/20)")
    elif csv_rows > 0:
        score += 5
        feedback_parts.append(f"CSV content invalid row count ({csv_rows}) or cutoff (5/20)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }