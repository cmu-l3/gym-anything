#!/usr/bin/env python3
"""
Verifier for configure_work_week task.

Task Goal:
- Mon-Thu: Full Day (Status 0)
- Fri: Half Day - Morning (Status 1)
- Sat-Sun: Non-working Day (Status 4)

Verification Logic:
- Check database values for ohrm_work_week table.
- Mon-Thu must equal 0.
- Fri must equal 1 (Half Day Morning).
- Sat-Sun must equal 4.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_work_week(traj, env_info, task_info):
    """
    Verify the work week configuration using database state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ==========================================================================
    # Load Result JSON from Container
    # ==========================================================================
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

    work_week = result.get('work_week', {})
    
    # Define expected status codes
    # Based on OrangeHRM defaults:
    # 0 = Full Day
    # 1 = Half Day - Morning
    # 2 = Half Day - Afternoon
    # 4 = Non-working Day (sometimes 3 in older versions, but setup uses 4)
    
    # We allow flexibility for "Non-working" (3 or 4) just in case
    NON_WORKING_CODES = [3, 4]
    
    score = 0
    feedback_parts = []
    
    # Check Mon-Thu (Should be Full Day = 0)
    mon_thu_ok = True
    for day in ['mon', 'tue', 'wed', 'thu']:
        val = work_week.get(day)
        if val != 0:
            mon_thu_ok = False
            feedback_parts.append(f"{day.capitalize()} is not Full Day (found {val})")
    
    if mon_thu_ok:
        score += 30
        feedback_parts.append("Mon-Thu are Full Days")

    # Check Sat-Sun (Should be Non-working)
    sat_sun_ok = True
    for day in ['sat', 'sun']:
        val = work_week.get(day)
        if val not in NON_WORKING_CODES:
            sat_sun_ok = False
            feedback_parts.append(f"{day.capitalize()} is not Non-working (found {val})")
            
    if sat_sun_ok:
        score += 30
        feedback_parts.append("Sat-Sun are Non-working")

    # Check Friday (Crucial Step: Should be Half Day - Morning = 1)
    # We definitely want it to NOT be 0 (Full) and NOT be 4 (Non-working)
    fri_val = work_week.get('fri')
    
    if fri_val == 1:
        score += 40
        feedback_parts.append("Friday is correctly set to Half Day - Morning")
    elif fri_val == 2:
        # Partial credit if they selected Afternoon instead of Morning
        score += 20
        feedback_parts.append("Friday is Half Day - Afternoon (Expected Morning)")
    elif fri_val == 0:
        feedback_parts.append("Friday is still Full Day (Unchanged)")
    elif fri_val in NON_WORKING_CODES:
        feedback_parts.append("Friday is Non-working (Wrong)")
    else:
        feedback_parts.append(f"Friday has unknown status: {fri_val}")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }