#!/usr/bin/env python3
"""
Verifier for Sakila Storage Intelligence Dashboard task.

Checks:
1. SQL Views created correctly (metadata + logic check).
2. Math logic for size/percentage calculations.
3. Filtering logic identifies fragmented tables.
4. CSV export exists, is recent, and contains correct data.
"""

import json
import logging
import os
import tempfile
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_storage_intelligence_dashboard(traj, env_info, task_info):
    """
    Verify the storage dashboard task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification results from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    # 1. View Creation (35 pts total)
    if result.get('view_metrics_exists', False):
        score += 20
        feedback_parts.append("View `v_storage_metrics` created (20 pts)")
    else:
        feedback_parts.append("View `v_storage_metrics` missing")

    if result.get('view_maint_exists', False):
        score += 15
        feedback_parts.append("View `v_maintenance_required` created (15 pts)")
    else:
        feedback_parts.append("View `v_maintenance_required` missing")

    # 2. Logic & Math (35 pts total)
    if result.get('logic_correct', False):
        score += 25
        feedback_parts.append("Metric calculations correct (25 pts)")
    else:
        feedback_parts.append("Metric calculations incorrect")

    if result.get('zero_div_handled', False):
        score += 10
        feedback_parts.append("Division by zero handled (10 pts)")
    else:
        feedback_parts.append("Zero division handling missing")

    # 3. Filtering & Export (30 pts total)
    if result.get('filter_logic_correct', False):
        score += 10
        feedback_parts.append("Filtering logic correctly identifies fragmented tables (10 pts)")
    else:
        feedback_parts.append("Filtering logic incorrect (fragmented tables not found)")

    # CSV Checks
    csv_exists = result.get('csv_exists', False)
    csv_mtime = result.get('csv_mtime', 0)
    task_start = result.get('task_start_time', 0)
    csv_valid = result.get('csv_content_valid', False)

    if csv_exists:
        if csv_mtime > task_start:
            score += 10
            feedback_parts.append("CSV export created during task (10 pts)")
            
            if csv_valid:
                score += 10
                feedback_parts.append("CSV content correct (contains target tables) (10 pts)")
            else:
                feedback_parts.append("CSV content invalid (missing target tables)")
        else:
            feedback_parts.append("CSV file is stale (created before task start)")
    else:
        feedback_parts.append("CSV export missing")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }