#!/usr/bin/env python3
"""
Verifier for create_work_location_assign_employees task.

Scoring Criteria:
1. Work Location Created (25 pts): Name "East Side Satellite Office" exists.
2. Work Location Type (10 pts): Type is "office".
3. Employee Assignments (60 pts): 20 pts each for Marc Demo, Audrey Peterson, Randall Lewis.
4. Anti-gaming (5 pts): Creation timestamp is after task start.

Pass Threshold: 70 points
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_work_location_assign_employees(traj, env_info, task_info):
    """
    Verify the Odoo HR task results.
    """
    # 1. Setup and retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Check for execution errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error during verification export: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 2. Verify Work Location Creation (25 pts)
    wl_found = result.get("work_location_found", False)
    wl_data = result.get("work_location", {})
    target_wl_id = wl_data.get("id")
    
    if wl_found:
        actual_name = wl_data.get("name", "")
        if actual_name == "East Side Satellite Office":
            score += 25
            feedback_parts.append("Work Location created correctly.")
        else:
            score += 15 # Partial credit for partial name match
            feedback_parts.append(f"Work Location created but name mismatch: '{actual_name}'.")
    else:
        feedback_parts.append("Work Location 'East Side Satellite Office' NOT found.")
        # If WL not found, we can't really pass other checks reliably, but we continue analysis
    
    # 3. Verify Location Type (10 pts)
    if wl_found:
        loc_type = wl_data.get("location_type")
        if loc_type == "office":
            score += 10
            feedback_parts.append("Location Type is correct (Office).")
        else:
            feedback_parts.append(f"Location Type incorrect: found '{loc_type}', expected 'office'.")
            
    # 4. Verify Employee Assignments (20 pts each, 60 total)
    employees = result.get("employees", {})
    target_emps = ["Marc Demo", "Audrey Peterson", "Randall Lewis"]
    
    for emp in target_emps:
        emp_data = employees.get(emp, {})
        if not emp_data.get("found"):
            feedback_parts.append(f"Employee {emp} not found in DB.")
            continue
            
        assigned_wl_id = emp_data.get("assigned_wl_id")
        assigned_wl_name = emp_data.get("assigned_wl_name", "")
        
        if target_wl_id and assigned_wl_id == target_wl_id:
            score += 20
            feedback_parts.append(f"{emp} assigned correctly.")
        elif assigned_wl_name and "East Side" in assigned_wl_name:
             # Partial credit if assigned to something looking similar but ID mismatch (unlikely if WL logic above held)
             score += 10
             feedback_parts.append(f"{emp} assigned to '{assigned_wl_name}' (partial match).")
        else:
            feedback_parts.append(f"{emp} NOT assigned correctly (Current: {assigned_wl_name or 'None'}).")

    # 5. Anti-gaming Timestamp Check (5 pts)
    # Ensure the record wasn't pre-existing
    task_start = result.get("task_start", 0)
    create_date_str = wl_data.get("create_date")
    
    if wl_found and create_date_str and task_start > 0:
        try:
            # Odoo returns UTC usually: "2023-10-25 10:00:00"
            create_dt = datetime.strptime(create_date_str, '%Y-%m-%d %H:%M:%S')
            create_ts = create_dt.timestamp()
            
            # Allow 120s clock drift/margin
            if create_ts >= (task_start - 120):
                score += 5
                feedback_parts.append("Work Location created during task session.")
            else:
                feedback_parts.append("Work Location appears to be pre-existing (Anti-gaming check).")
        except ValueError:
            feedback_parts.append("Could not parse creation timestamp.")
    elif wl_found:
        # If we found it but can't verify time, give benefit of doubt or 0? 
        # Usually 0 in strict anti-gaming.
        pass

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }