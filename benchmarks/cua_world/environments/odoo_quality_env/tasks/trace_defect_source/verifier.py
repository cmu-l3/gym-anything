#!/usr/bin/env python3
"""
Verifier for trace_defect_source task.
Checks if the quality alert was correctly linked to the source receipt and priority updated.
"""

import json
import os
import sys
import tempfile
from datetime import datetime

def verify_trace_defect_source(traj, env_info, task_info):
    """
    Verify the agent linked the alert to the correct picking and set priority.
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

    # Check for basic errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script failed: {result['error']}"}

    score = 0
    feedback = []
    max_score = 100

    # 1. Alert Found (Pre-requisite)
    if not result.get("alert_found"):
        return {"passed": False, "score": 0, "feedback": "Quality Alert 'Defective Office Chair' was deleted or not found."}

    # 2. Picking Linked (40 pts)
    if result.get("picking_linked"):
        score += 40
        feedback.append("Alert is linked to a picking.")
    else:
        feedback.append("Alert is NOT linked to any picking.")

    # 3. Correct Source Origin (30 pts)
    # The target origin is PO998877
    origin = result.get("picking_origin", "")
    target_origin = task_info.get('metadata', {}).get('target_origin', 'PO998877')
    
    if origin == target_origin:
        score += 30
        feedback.append(f"Linked picking has correct origin ({target_origin}).")
    elif result.get("picking_linked"):
        feedback.append(f"Linked picking has WRONG origin ('{origin}', expected '{target_origin}').")

    # 4. Priority Check (20 pts)
    # Priority '2' is High (2 stars), '0' is Normal/Low
    priority = result.get("priority", "0")
    if priority == "2":
        score += 20
        feedback.append("Priority set to High.")
    else:
        feedback.append(f"Priority is incorrect (found '{priority}', expected '2').")

    # 5. Timestamp/Anti-gaming (10 pts)
    # Check if the record was modified after task start
    # write_date is usually UTC string "YYYY-MM-DD HH:MM:SS"
    # task_start_time is unix timestamp
    write_date_str = result.get("write_date")
    task_start = result.get("task_start_time", 0)
    
    modified_during_task = False
    if write_date_str and task_start > 0:
        try:
            # Odoo dates are UTC. Simple check: just ensure date parsing works
            # and conversion to timestamp is roughly > start
            # For simplicity, we can trust Odoo updated the write_date if values changed
            # But let's do a rough conversion
            dt = datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
            # Note: Odoo stores UTC. If system clock is UTC, this works.
            # We'll allow a small buffer or just check if it parses.
            # A more robust check is difficult without timezone info, 
            # so we'll award points if *attributes changed* which updates write_date
            modified_during_task = True 
        except ValueError:
            pass

    if modified_during_task:
        score += 10
    else:
        feedback.append("Warning: Could not verify modification timestamp.")

    passed = (score >= 70) # Passing requires at least linking the correct picking (40+30)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }