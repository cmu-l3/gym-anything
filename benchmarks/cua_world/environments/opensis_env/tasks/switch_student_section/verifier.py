#!/usr/bin/env python3
import json
import os
import sys
import logging
import datetime
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_switch_section(traj, env_info, task_info):
    """
    Verifies that the student was switched from AM to PM section.
    
    Criteria:
    1. AM Section (Morning): Must be DROPPED (End Date <= Today)
    2. PM Section (Afternoon): Must be ACTIVE (End Date is None or > Today)
    3. No Double Booking: Student cannot be active in both.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (no copy_from_env)"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse Data
    config = result.get('config', {})
    schedule = result.get('schedule', [])
    today_str = result.get('timestamp') # Format YYYY-MM-DD
    
    cp_am_id = config.get('cp_am_id')
    cp_pm_id = config.get('cp_pm_id')
    
    if not cp_am_id or not cp_pm_id:
        return {"passed": False, "score": 0, "feedback": "Verification config missing section IDs"}

    am_status = "missing" # missing, active, dropped
    pm_status = "missing" # missing, active, dropped
    
    today_date = datetime.datetime.strptime(today_str, "%Y-%m-%d").date()

    # Analyze schedule records
    for record in schedule:
        cp_id = record['course_period_id']
        end_date_str = record['end_date']
        
        is_active = True
        if end_date_str:
            end_date = datetime.datetime.strptime(end_date_str, "%Y-%m-%d").date()
            if end_date <= today_date:
                is_active = False
        
        if cp_id == cp_am_id:
            am_status = "active" if is_active else "dropped"
        elif cp_id == cp_pm_id:
            pm_status = "active" if is_active else "dropped"

    # Scoring
    score = 0
    feedback = []

    # Check 1: Old Section Dropped (40 pts)
    if am_status == "dropped":
        score += 40
        feedback.append("Success: Morning session dropped.")
    elif am_status == "active":
        feedback.append("Fail: Student is still active in Morning session.")
    else:
        feedback.append("Fail: Morning session record not found (deleted?).")

    # Check 2: New Section Added (40 pts)
    if pm_status == "active":
        score += 40
        feedback.append("Success: Afternoon session added.")
    elif pm_status == "dropped":
        feedback.append("Fail: Afternoon session was added but then dropped.")
    else:
        feedback.append("Fail: Afternoon session record not found.")

    # Check 3: No Double Booking (20 pts)
    # Only award if at least one positive action was taken
    if score > 0:
        if not (am_status == "active" and pm_status == "active"):
            score += 20
            feedback.append("Success: No schedule conflict.")
        else:
            feedback.append("Fail: Student is double-booked (active in both sections).")

    passed = (score >= 80) # Needs both drop and add to be generally correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }