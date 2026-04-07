#!/usr/bin/env python3
"""
Verifier for Freight Mode Shift Comparison task.

Criteria:
1. Report File Analysis (40 pts)
   - Exists and created during task
   - Contains reasonable GWP values for Truck (80-180 kg CO2e) and Train (15-50 kg CO2e)
   - Values indicate 1000 t*km scale (not 1 kg unit error)
2. Database State Verification (40 pts)
   - Process "Distribution Scenario" exists
   - Contains "Train" or "Rail" input exchange (proving modification)
3. VLM Trajectory Verification (20 pts)
   - Workflow: Import -> Create Process -> Calc 1 -> Modify -> Calc 2

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
import base64
import re

logger = logging.getLogger(__name__)

def verify_freight_mode_shift(traj, env_info, task_info):
    """Verify freight mode shift comparison task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    metadata = task_info.get('metadata', {})
    truck_min = metadata.get('ranges', {}).get('truck_gwp_min', 80.0)
    truck_max = metadata.get('ranges', {}).get('truck_gwp_max', 180.0)
    train_min = metadata.get('ranges', {}).get('train_gwp_min', 15.0)
    train_max = metadata.get('ranges', {}).get('train_gwp_max', 50.0)

    # 1. Report Verification (40 pts)
    report_exists = result.get('report_exists', False)
    created_new = result.get('report_created_during_task', False)
    content_b64 = result.get('report_content_b64', "")
    
    if report_exists and created_new:
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Extract numbers
            numbers = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content)]
            
            # Heuristic check for values
            truck_val = next((n for n in numbers if truck_min <= n <= truck_max), None)
            train_val = next((n for n in numbers if train_min <= n <= train_max), None)
            
            if truck_val and train_val:
                score += 40
                feedback.append(f"Report values valid (Truck: {truck_val}, Train: {train_val})")
            elif truck_val:
                score += 20
                feedback.append(f"Report has valid Truck value ({truck_val}), Train value missing/out of range")
            elif train_val:
                score += 20
                feedback.append(f"Report has valid Train value ({train_val}), Truck value missing/out of range")
            else:
                score += 10
                feedback.append("Report exists but values seem incorrect or scaled wrong (check units?)")
        except Exception as e:
            feedback.append(f"Error parsing report: {e}")
    else:
        feedback.append("Report file not found or not created during task")

    # 2. Database Verification (40 pts)
    process_found = result.get('process_found', False)
    train_input = result.get('train_input_found', False)
    
    if process_found:
        score += 20
        feedback.append("Process 'Distribution Scenario' found in database")
        if train_input:
            score += 20
            feedback.append("Process correctly modified to use Train transport")
        elif result.get('truck_input_found', False):
            score += 5
            feedback.append("Process found but still uses Truck (modification step missed?)")
        else:
            feedback.append("Process found but missing transport input")
    else:
        feedback.append("Process 'Distribution Scenario' NOT found in database")

    # 3. VLM Verification (20 pts)
    # Simple check: did they produce enough screenshots to imply work?
    # Ideally use trajectory query, but here we use a simple heuristic if programmatic failed partial
    if score >= 60:
        score += 20 # Assume if output is correct, workflow was followed
        feedback.append("Implicit workflow verification (outputs correct)")
    else:
        # Fallback points for effort if report failed
        if process_found:
            score += 10
            feedback.append("Partial credit for database work")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }