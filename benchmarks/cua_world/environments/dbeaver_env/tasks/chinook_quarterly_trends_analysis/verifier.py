#!/usr/bin/env python3
"""
Verifier for chinook_quarterly_trends_analysis@1

Criteria:
1. DBeaver Connection 'Chinook' exists (10 pts)
2. View 'v_quarterly_analytics' exists in DB (20 pts)
3. SQL Script exists (10 pts)
4. CSV Output exists and created during task (10 pts)
5. Data Accuracy (Checked via CSV content vs Ground Truth):
   - Quarterly Revenue matches (15 pts)
   - YoY Growth Calculation matches (20 pts)
   - Rolling Average Calculation matches (15 pts)

Total: 100 pts
Pass Threshold: 65 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_quarterly_trends_analysis(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. DBeaver Connection (10 pts)
    if result.get('connection_exists'):
        score += 10
        feedback.append("DBeaver connection 'Chinook' confirmed.")
    else:
        feedback.append("DBeaver connection 'Chinook' not found.")

    # 2. View Existence (20 pts)
    if result.get('view_exists'):
        score += 20
        feedback.append("View 'v_quarterly_analytics' created in database.")
        
        # Check columns loosely
        cols = result.get('view_columns', '').lower()
        required = ['year', 'quarter', 'quarterlyrevenue', 'yoygrowthpct', 'rollingavgrevenue']
        missing = [c for c in required if c not in cols]
        if missing:
            feedback.append(f"Warning: View might be missing columns: {missing}")
    else:
        feedback.append("View 'v_quarterly_analytics' NOT found in database.")

    # 3. SQL Script (10 pts)
    if result.get('sql_script_exists'):
        score += 10
        feedback.append("SQL script saved.")
    else:
        feedback.append("SQL creation script not found.")

    # 4. CSV Existence & Freshness (10 pts)
    if result.get('csv_exists') and result.get('csv_created_during_task'):
        score += 10
        feedback.append("CSV export found and created during task.")
    elif result.get('csv_exists'):
        score += 5
        feedback.append("CSV export found but timestamp is old (pre-existing?).")
    else:
        feedback.append("CSV export file not found.")

    # 5. Data Accuracy (50 pts)
    # Compare CSV extracted test values against Ground Truth
    csv_vals = result.get('csv_test_values', {})
    gt_vals = result.get('ground_truth', {})
    
    if csv_vals.get('found'):
        # Revenue (15 pts) - Tolerance +/- 1.0
        agent_rev = csv_vals.get('revenue', 0)
        gt_rev = gt_vals.get('expected_revenue', 0)
        if abs(agent_rev - gt_rev) <= 1.0:
            score += 15
            feedback.append(f"Revenue accuracy verified ({agent_rev}).")
        else:
            feedback.append(f"Revenue mismatch: Got {agent_rev}, Expected ~{gt_rev}.")

        # YoY Growth (20 pts) - Tolerance +/- 0.5%
        # This tests the Window Function LAG logic
        agent_yoy = csv_vals.get('yoy', 0)
        gt_yoy = gt_vals.get('expected_yoy', 0)
        if gt_yoy is not None and abs(agent_yoy - gt_yoy) <= 0.5:
            score += 20
            feedback.append(f"YoY Growth accuracy verified ({agent_yoy}%).")
        else:
            feedback.append(f"YoY Growth mismatch: Got {agent_yoy}%, Expected ~{gt_yoy}%.")

        # Rolling Avg (15 pts) - Tolerance +/- 1.0
        # This tests the Window Function ROWS BETWEEN logic
        agent_roll = csv_vals.get('rolling', 0)
        gt_roll = gt_vals.get('expected_rolling', 0)
        if abs(agent_roll - gt_roll) <= 1.0:
            score += 15
            feedback.append(f"Rolling Average accuracy verified ({agent_roll}).")
        else:
            feedback.append(f"Rolling Average mismatch: Got {agent_roll}, Expected ~{gt_roll}.")
            
    else:
        feedback.append("Could not verify data accuracy (Test quarter 2011 Q3 not found in CSV).")

    # Final tally
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }