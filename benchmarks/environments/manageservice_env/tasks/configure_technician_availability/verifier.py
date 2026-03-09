#!/usr/bin/env python3
"""
Verifier for configure_technician_availability task.
Verifies that the correct technician has leave booked for the correct date
with the correct backup technician.
"""

import json
import os
import sys
import datetime
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_technician_availability(traj, env_info, task_info):
    """
    Verify technician availability configuration.
    
    Expected:
    1. Leave record exists for John Doe (target_technician)
    2. Date matches "tomorrow" (relative to task start)
    3. Backup technician is Sarah Smith
    4. Leave was created during the task
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result from container
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
            
    # Check for extraction errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}
        
    score = 0
    feedback_parts = []
    
    # 1. Validate IDs
    john_id = result.get('john_doe_id')
    sarah_id = result.get('sarah_smith_id')
    
    if not john_id or not sarah_id:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to identify technicians in database. Setup might have failed."
        }

    # 2. Calculate Expected Date Range
    # target_date_str is "YYYY-MM-DD"
    target_date_str = result.get('target_date_str')
    if not target_date_str:
        return {"passed": False, "score": 0, "feedback": "Target date not recorded"}
        
    try:
        # Create start/end timestamps for the target date in ms
        # SDP dates are often stored as local time midnight in ms
        target_dt = datetime.datetime.strptime(target_date_str, "%Y-%m-%d")
        
        # We allow a window because of potential timezone mismatches between OS and DB
        # Window: Target Date 00:00 to Target Date 23:59
        target_start_ts = target_dt.timestamp() * 1000
        target_end_ts = (target_dt + datetime.timedelta(days=1)).timestamp() * 1000
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Date parsing error: {e}"}

    # 3. Find Matching Leave Record
    leaves = result.get('leaves', [])
    valid_leave = None
    
    for leave in leaves:
        leave_date = leave.get('leave_date_ms', 0)
        
        # Check date (allow 24h window around target due to potential timezone hell)
        # Actually, SDP usually stores midnight of the day.
        # We'll check if it falls strictly within the target day + buffer
        # Buffer: +/- 12 hours from midnight to catch timezone shifts
        
        # Precise check: Is it "tomorrow"?
        # Let's check if the leave date string matches target date string
        leave_dt = datetime.datetime.fromtimestamp(leave_date / 1000.0)
        leave_date_str = leave_dt.strftime("%Y-%m-%d")
        
        # Check timestamp creation (Anti-gaming)
        created_date = leave.get('created_date_ms', 0)
        task_start_ms = result.get('task_start_time_sec', 0) * 1000
        
        is_recent = created_date > task_start_ms
        is_correct_date = (leave_date_str == target_date_str)
        
        if is_correct_date:
            valid_leave = leave
            # If we found one with correct date, we stop looking?
            # Ideally we want the one created RECENTLY.
            if is_recent:
                break
    
    # Scoring
    if valid_leave:
        score += 30
        feedback_parts.append(f"Leave record found for {target_date_str}")
        
        # Check Backup Tech
        backup_id = valid_leave.get('backup_tech_id')
        if str(backup_id) == str(sarah_id):
            score += 40
            feedback_parts.append("Backup technician assigned correctly (Sarah Smith)")
        else:
            feedback_parts.append(f"Incorrect backup technician ID: {backup_id} (Expected {sarah_id})")
            
        # Check Creation Time
        created_date = valid_leave.get('created_date_ms', 0)
        task_start_ms = result.get('task_start_time_sec', 0) * 1000
        if created_date > task_start_ms:
            score += 20
            feedback_parts.append("Leave created during task session")
        else:
            feedback_parts.append("Warning: Leave record predates task start (stale data?)")
            
        # Check Leave Type
        leave_type = valid_leave.get('leave_type', '')
        if "Sick" in leave_type or "Leave" in leave_type:
            score += 10
            feedback_parts.append(f"Leave type valid: {leave_type}")
        else:
            feedback_parts.append(f"Leave type unexpected: {leave_type}")
            
    else:
        feedback_parts.append(f"No leave record found for date {target_date_str} for John Doe")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }