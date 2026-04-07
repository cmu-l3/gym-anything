#!/usr/bin/env python3
"""
Verifier for financial_grouping_sets_report task.

Scoring Breakdown (100 pts):
- View exists: 10 pts
- Optimization (No UNION used): 10 pts
- Grand Total Correct: 20 pts
- Region Subtotals Correct: 20 pts
- Category Subtotals Correct: 20 pts
- Labels Correct ('All Regions'/'All Categories'): 20 pts

Pass threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_financial_grouping_sets_report(traj, env_info, task_info):
    """
    Verifies that the agent created an optimized view using GROUPING SETS
    with correct aggregation levels and labels.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "grouping_result.json")
        try:
            copy_from_env("/tmp/grouping_result.json", result_path)
            if not os.path.exists(result_path):
                return {"passed": False, "score": 0, "feedback": "Result file not found."}
            
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    if result.get("db_error"):
        feedback_parts.append(f"DB Error: {result['db_error']}")

    # 1. View Exists (10 pts)
    if result.get("view_exists"):
        score += 10
        feedback_parts.append("View REVENUE_SUMMARY_VIEW exists (+10)")
    else:
        return {"passed": False, "score": 0, "feedback": "View REVENUE_SUMMARY_VIEW not found."}

    # 2. Optimization Check (10 pts)
    # Penalize UNION usage, Reward GROUPING SETS/ROLLUP/CUBE
    if result.get("ddl_uses_union"):
        feedback_parts.append("Optimization FAIL: View uses UNION (expected GROUPING SETS) (0 pts)")
    else:
        if result.get("ddl_uses_grouping"):
            score += 10
            feedback_parts.append("Optimization PASS: View uses grouping sets/rollup/cube (+10)")
        else:
            # Maybe they did it some other valid way (unlikely without union or grouping sets), 
            # or DDL check was fuzzy. Give partial credit if NO UNION found.
            score += 5
            feedback_parts.append("Optimization PARTIAL: No UNION found, but GROUPING keywords not detected (+5)")

    # 3. Grand Total (20 pts)
    if result.get("grand_total_match"):
        score += 20
        feedback_parts.append("Grand Total calculation correct (+20)")
    else:
        feedback_parts.append(f"Grand Total incorrect or missing. Expected: {result.get('actual_grand_total')}, Got: {result.get('view_grand_total')} (0 pts)")

    # 4. Region Subtotals (20 pts)
    if result.get("region_subtotal_match"):
        score += 20
        feedback_parts.append("Region subtotals correct (+20)")
    else:
        feedback_parts.append("Region subtotals incorrect (0 pts)")

    # 5. Category Subtotals (20 pts)
    if result.get("category_subtotal_match"):
        score += 20
        feedback_parts.append("Category subtotals correct (+20)")
    else:
        feedback_parts.append("Category subtotals incorrect (0 pts)")

    # 6. Labels Correct (20 pts)
    # Checked via the specific query for 'All Regions'/'All Categories' in export script
    if result.get("labels_correct"):
        score += 20
        feedback_parts.append("Labels 'All Regions'/'All Categories' applied correctly (+20)")
    else:
        feedback_parts.append("Labels incorrect (NULLs or wrong text used) (0 pts)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }