#!/usr/bin/env python3
"""
Verifier for inventory_fill_down_cleanup task.

Criteria:
1. PBIX File Saved (10 pts)
2. CSV Export Exists (10 pts)
3. Correct Data Calculation (Fill Down Applied) (50 pts)
   - Checks if Electronics total is ~12,500
   - If Fill Down was skipped, it would likely be 10,000 or have a blank category
4. Visuals Correct (30 pts)
   - Clustered Bar Chart present
   - Data Labels enabled
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_inventory_fill_down_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata & Results
    expected_value = task_info.get('metadata', {}).get('target_value', 12500)
    tolerance = task_info.get('metadata', {}).get('tolerance', 100)
    
    pbix_exists = result.get('pbix_exists', False)
    csv_exists = result.get('csv_exists', False)
    actual_value = result.get('electronics_value', 0)
    visuals = result.get('visuals_found', [])
    
    score = 0
    feedback = []

    # 3. Scoring Logic
    
    # Criterion 1: File Saved
    if pbix_exists and result.get('pbix_size', 0) > 1000:
        score += 10
        feedback.append("Report saved.")
    else:
        feedback.append("Report file not found or empty.")

    # Criterion 2: CSV Exported
    if csv_exists:
        score += 10
        feedback.append("Data exported to CSV.")
    else:
        feedback.append("Summary CSV not found.")

    # Criterion 3: Correct Value (The Core Test)
    # 12,500 is correct. 10,000 implies Fill Down missing.
    try:
        val = float(actual_value)
        if abs(val - expected_value) <= tolerance:
            score += 50
            feedback.append(f"Correct Electronics total ({val}). Fill Down applied successfully.")
        elif abs(val - 10000) <= tolerance:
            score += 10
            feedback.append(f"Electronics total is {val} (expected {expected_value}). It seems 'Fill Down' was missed.")
        else:
            feedback.append(f"Incorrect Electronics total: {val}. Expected ~{expected_value}.")
    except:
        feedback.append("Could not parse numeric value from export.")

    # Criterion 4: Visuals
    if 'clusteredBarChart' in visuals:
        score += 20
        feedback.append("Clustered Bar Chart found.")
    else:
        feedback.append("Bar chart not found in layout.")

    if 'dataLabels' in visuals:
        score += 10
        feedback.append("Data labels enabled.")
    
    # Pass check
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }