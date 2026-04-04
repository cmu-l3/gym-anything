#!/usr/bin/env python3
"""
Verifier for chinook_daily_revenue_gaps@1

This script scores the task based on the analysis performed in export_result.sh.
It emphasizes correct data density (filling gaps), handling leap years, and accurate aggregations.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_daily_revenue_gaps(traj, env_info, task_info):
    """
    Verify the daily revenue gap analysis task.
    
    Scoring Breakdown (100 pts total):
    - Connection Created (10 pts)
    - CSV Exists (10 pts)
    - Row Count Correct (20 pts): Must be 366 (leap year).
    - Date Continuity (20 pts): Start/End dates match, leap day exists.
    - Zero-Sales Handling (20 pts): Gaps filled with 0.
    - Weekend Logic (10 pts): Correctly identified Sat/Sun.
    - Grand Total Match (10 pts): Sum matches DB total (integrity check).
    
    Pass Threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Connection Created (10 pts)
    if result.get('dbeaver_connection_exists'):
        score += 10
        feedback.append("DBeaver connection confirmed.")
    else:
        feedback.append("No DBeaver connection to Chinook found.")

    # 2. CSV Exists (10 pts)
    if result.get('csv_exists'):
        score += 10
        feedback.append("Output CSV file found.")
    else:
        return {"passed": False, "score": score, "feedback": "Output CSV not found. Cannot score data quality."}

    # 3. Row Count Correct (20 pts)
    # 2012 is a leap year = 366 days.
    row_count = int(result.get('row_count', 0))
    if row_count == 366:
        score += 20
        feedback.append("Row count is exactly 366 (correct for 2012 leap year).")
    elif row_count == 365:
        score += 10
        feedback.append("Row count is 365. Missed leap day (Feb 29). Partial credit.")
    else:
        feedback.append(f"Row count is {row_count}. Expected 366.")

    # 4. Date Continuity (20 pts)
    start_correct = result.get('start_date_correct')
    end_correct = result.get('end_date_correct')
    leap_day = result.get('leap_day_present')
    
    if start_correct and end_correct and leap_day:
        score += 20
        feedback.append("Date range covers full year including Feb 29.")
    elif start_correct and end_correct:
        score += 10
        feedback.append("Date range covers year but missing leap day check.")
    else:
        feedback.append("Date range incomplete.")

    # 5. Zero-Sales Handling (20 pts)
    # This proves they did a LEFT JOIN to a generated date sequence, not just an INNER JOIN
    if result.get('gaps_filled_with_zero'):
        score += 20
        feedback.append("Gap filling verified: Days with zero sales exist.")
    else:
        feedback.append("Gap filling failed: No zero-sales days found. Likely used INNER JOIN or didn't generate missing dates.")

    # 6. Weekend Logic (10 pts)
    if result.get('weekend_logic_correct'):
        score += 10
        feedback.append("Weekend logic is correct (Sun=Yes, Mon=No).")
    else:
        feedback.append("Weekend logic incorrect or column missing.")

    # 7. Grand Total Match (10 pts)
    if result.get('total_revenue_match'):
        score += 10
        feedback.append("Total revenue matches database ground truth.")
    else:
        feedback.append(f"Revenue mismatch. Agent: {result.get('agent_revenue')}, GT: {result.get('ground_truth_revenue')}")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }