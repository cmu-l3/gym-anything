#!/usr/bin/env python3
"""
Verifier for generate_daily_usage_report task.
Compares agent's JSON report against ground truth calculated from the DB.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_daily_usage_report(traj, env_info, task_info):
    """
    Verify the daily usage report.
    
    Criteria:
    1. Output file exists and is valid JSON.
    2. JSON contains exactly 7 entries.
    3. Dates match the previous 7 UTC days.
    4. kWh values are within tolerance (5%) of ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance_percent = metadata.get('tolerance_percent', 5.0)

    # Copy result
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

    # 1. Check existence
    if not result.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file /home/ga/daily_usage_report.json not found."
        }
        
    # 2. Check Content Structure
    agent_data = result.get('agent_content')
    if agent_data is None:
        return {
            "passed": False, 
            "score": 10, 
            "feedback": "Output file exists but contains invalid JSON."
        }
    
    if not isinstance(agent_data, list):
        return {
            "passed": False, 
            "score": 10, 
            "feedback": "JSON root must be a list of objects."
        }

    ground_truth = result.get('ground_truth', [])
    
    # 3. Check Length
    if len(agent_data) != 7:
        return {
            "passed": False, 
            "score": 20, 
            "feedback": f"Expected 7 days of data, found {len(agent_data)}."
        }

    # 4. Compare Values
    score = 20 # Base score for valid file
    max_score = 100
    points_per_day = 80 / 7  # ~11.4 points per correct day
    
    feedback_details = []
    
    # Sort both lists by date to ensure alignment
    try:
        agent_data.sort(key=lambda x: x['date'])
        ground_truth.sort(key=lambda x: x['date'])
    except KeyError:
        return {
            "passed": False, 
            "score": 20, 
            "feedback": "JSON objects missing 'date' key."
        }

    correct_days = 0
    
    for i, gt_day in enumerate(ground_truth):
        if i >= len(agent_data):
            break
            
        agent_day = agent_data[i]
        
        # Check Date
        if agent_day.get('date') != gt_day['date']:
            feedback_details.append(f"Day {i+1}: Date mismatch (Expected {gt_day['date']}, Got {agent_day.get('date')})")
            continue
            
        # Check kWh
        try:
            agent_val = float(agent_day.get('kwh', 0))
            gt_val = float(gt_day['kwh'])
            
            # Avoid division by zero
            if gt_val == 0:
                diff_percent = 0 if agent_val == 0 else 100
            else:
                diff_percent = abs(agent_val - gt_val) / gt_val * 100
            
            if diff_percent <= tolerance_percent:
                score += points_per_day
                correct_days += 1
            else:
                feedback_details.append(f"Day {gt_day['date']}: Value {agent_val} deviates by {diff_percent:.1f}% from expected {gt_val:.2f}")
                
        except (ValueError, TypeError):
             feedback_details.append(f"Day {i+1}: Invalid number format")

    final_score = min(100, int(score))
    
    # Anti-gaming: Check if file was created during task
    if not result.get('file_created_during_task'):
        feedback_details.append("Warning: Output file timestamp indicates it wasn't modified during task.")
        final_score = min(final_score, 50) # Cap score if file seems stale

    passed = final_score >= 70
    
    feedback_str = f"Correctly analyzed {correct_days}/7 days."
    if feedback_details:
        feedback_str += " Errors: " + "; ".join(feedback_details[:3])
        if len(feedback_details) > 3:
            feedback_str += "..."

    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback_str
    }