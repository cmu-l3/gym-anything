#!/usr/bin/env python3
"""
Verifier for reorder_menu_categories task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorder_menu_categories(traj, env_info, task_info):
    """
    Verifies that the 'BEVERAGES' category sort order was changed to 0.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract values
    try:
        # Sort order comes as string from shell script parsing
        final_sort = int(result.get("final_sort_order", -1))
    except (ValueError, TypeError):
        final_sort = -1
        
    initial_sort = result.get("initial_sort_order", 99)
    app_running = result.get("app_was_running", False)
    category_name = result.get("category_name", "")

    # Criterion 1: Category exists (20 pts)
    if final_sort != -1 and "BEVERAGE" in category_name.upper():
        score += 20
        feedback_parts.append("Category 'BEVERAGES' found in database")
    else:
        feedback_parts.append("Category 'BEVERAGES' not found or deleted")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Sort Order Modified (30 pts)
    if final_sort != initial_sort:
        score += 30
        feedback_parts.append(f"Sort order modified (Initial: {initial_sort}, Final: {final_sort})")
    else:
        feedback_parts.append("Sort order unchanged")

    # Criterion 3: Sort Order is exactly 0 (50 pts)
    if final_sort == 0:
        score += 50
        feedback_parts.append("Sort order is correctly set to 0")
    else:
        feedback_parts.append(f"Sort order {final_sort} is not 0")

    # Penalty if app wasn't running (it should be running at end of task)
    if not app_running:
        feedback_parts.append("Warning: Application was closed prematurely")
        # Optional: deduct points or just warn

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }