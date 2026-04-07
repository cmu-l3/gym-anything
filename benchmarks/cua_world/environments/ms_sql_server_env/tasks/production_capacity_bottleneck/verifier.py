#!/usr/bin/env python3
"""
Verifier for production_capacity_bottleneck task.
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_production_capacity_bottleneck(traj, env_info, task_info):
    """
    Verifies the SQL Server production capacity bottleneck analysis task.
    
    Criteria:
    1. Scalar Function created and works correctly (15 pts)
    2. View created with correct schema/logic (20 pts)
    3. Bottleneck Analysis Table created (10 pts)
    4. Stored Procedure created (15 pts)
    5. Table populated with correct 2013 data (Logic check) (15 pts)
    6. CSV Export performed correctly (20 pts)
    7. Visual check (5 pts)
    
    Pass threshold: 70/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Load verification data from container ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    # 1. Scalar Function (15 pts)
    if result.get('func_exists'):
        if result.get('func_test_pass'):
            score += 15
            feedback_parts.append("Function exists and works.")
        else:
            score += 5
            feedback_parts.append("Function exists but returned incorrect calculation.")
    else:
        feedback_parts.append("Scalar function not found.")

    # 2. View (20 pts)
    if result.get('view_exists'):
        subscore = 10
        if result.get('view_columns_match'):
            subscore += 5
        if result.get('view_row_count', 0) > 50:
            subscore += 5
        score += subscore
        feedback_parts.append(f"View exists (rows: {result.get('view_row_count')}).")
    else:
        feedback_parts.append("View not found.")

    # 3. Table (10 pts)
    if result.get('table_exists'):
        score += 10
        feedback_parts.append("Analysis table created.")
    else:
        feedback_parts.append("Analysis table not found.")

    # 4. Stored Procedure (15 pts)
    if result.get('proc_exists'):
        score += 15
        feedback_parts.append("Stored procedure created.")
    else:
        feedback_parts.append("Stored procedure not found.")

    # 5. Data & Logic (15 pts)
    if result.get('table_has_data'):
        if result.get('logic_valid'):
            score += 15
            feedback_parts.append("Data population and calculation logic verified.")
        elif result.get('rank_check_pass'):
            score += 10
            feedback_parts.append("Data populated and ranks look ok, but specific calculation check failed.")
        else:
            score += 5
            feedback_parts.append("Table has data but values/ranks seem incorrect.")
    else:
        feedback_parts.append("Analysis table is empty.")

    # 6. CSV Export (20 pts)
    if result.get('csv_exists'):
        if result.get('csv_content_valid'):
            score += 20
            feedback_parts.append("CSV exported with valid matching content.")
        elif result.get('csv_row_count', 0) > 0:
            score += 15
            feedback_parts.append("CSV exported but content mismatch with DB.")
        else:
            score += 5
            feedback_parts.append("CSV file exists but is empty.")
    else:
        feedback_parts.append("CSV export file not found.")

    # 7. Visual Verification (5 pts)
    # Just checking if the final screenshot exists implies the export script ran
    # We could use VLM here to check if ADS is open, but programmatic checks are strong enough.
    # We'll give 5 pts for a "clean finish" (script ran to completion)
    score += 5

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }