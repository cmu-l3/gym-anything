#!/usr/bin/env python3
"""
Verifier for create_custom_alarm task.
Verifies that the agent created a specific custom alarm configuration in Odoo.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_alarm(traj, env_info, task_info):
    """
    Verify that the 'Q2 Financial Review' event has a custom 3-hour email alarm.
    
    Criteria:
    1. Event must have at least one alarm.
    2. Alarm must be type 'email'.
    3. Alarm must represent 3 hours (duration=3 & interval=hours OR duration=180 & interval=minutes).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Retrieve result JSON
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

    # Check database results
    if not result.get('event_found'):
        return {"passed": False, "score": 0, "feedback": "Target event 'Q2 Financial Review' not found in database."}

    alarms = result.get('alarms_found', [])
    
    if not alarms:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The event 'Q2 Financial Review' has no alarms configured."
        }
    
    # Event has alarms (20 pts)
    score += 20
    feedback_parts.append("Event has alarm(s)")
    
    correct_alarm_found = False
    best_alarm_score = 0
    
    # Check each alarm to see if it matches the requirements
    for alarm in alarms:
        current_alarm_score = 0
        alarm_feedback = []
        
        # Check Type (25 pts)
        is_email = (alarm.get('alarm_type') == 'email')
        if is_email:
            current_alarm_score += 25
            alarm_feedback.append("Type: Email")
        else:
            alarm_feedback.append(f"Type: {alarm.get('alarm_type')}")
            
        # Check Duration/Unit combo (50 pts total)
        duration = alarm.get('duration')
        interval = alarm.get('interval')
        
        # Logic for 3 Hours OR 180 Minutes
        is_3_hours = (duration == 3 and interval == 'hours')
        is_180_mins = (duration == 180 and interval == 'minutes')
        
        if is_3_hours or is_180_mins:
            current_alarm_score += 50 # 25 for duration + 25 for unit
            alarm_feedback.append("Duration: 3 Hours")
        elif duration == 3:
            current_alarm_score += 25
            alarm_feedback.append(f"Duration: 3 (Wrong Unit: {interval})")
        else:
            alarm_feedback.append(f"Duration: {duration} {interval}")
            
        # Check if this is the winning alarm configuration
        if current_alarm_score > best_alarm_score:
            best_alarm_score = current_alarm_score
            
        if is_email and (is_3_hours or is_180_mins):
            correct_alarm_found = True
            # Bonus 5 points for perfect execution implied
            score += 5 
            break
            
    # Add best alarm score to base score
    score += best_alarm_score
    
    # Final cleanup of score cap
    if score > 100: score = 100
    
    if correct_alarm_found:
        feedback_parts.append("Correct 3-hour email alarm configured")
    else:
        feedback_parts.append("No alarm matched full criteria (Email + 3 Hours)")

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }