#!/usr/bin/env python3
"""
Verifier for configure_operational_hours task.
Verifies that the agent correctly configured business hours in the database.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_operational_hours(traj, env_info, task_info):
    """
    Verify the operational hours configuration.
    Strategy:
    1. Check Database state (Primary)
    2. Check Screenshot via VLM (Secondary/Fallback)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. DATABASE VERIFICATION
    # =========================================================
    db_raw = result.get('db_output_raw', '').strip()
    initial_db = result.get('initial_db_output', '').strip()
    
    # Anti-gaming: Did state change?
    if db_raw == initial_db and db_raw != "":
        feedback_parts.append("Operational hours unchanged from initial state (Did nothing)")
        return {"passed": False, "score": 0, "feedback": "Did nothing: " + " | ".join(feedback_parts)}

    # Parse DB Output
    # Expected format: day|start|end|is_working
    # SDP days usually: 1=Sunday, 2=Monday... OR 0=Sunday... 
    # We will try to map loosely based on count.
    # Target:
    #   Mon-Fri: 08:00 - 18:00
    #   Sat: 09:00 - 13:00
    #   Sun: Closed
    
    # Map to structure: {day_id: {start, end, active}}
    schedule = {}
    if db_raw:
        lines = db_raw.split('\n')
        for line in lines:
            parts = line.split('|')
            if len(parts) >= 4:
                # Assuming order: day, start, end, active
                d_id = parts[0].strip()
                start = parts[1].strip()
                end = parts[2].strip()
                active = parts[3].strip().lower()
                
                # Normalize time (remove seconds if present: 08:00:00 -> 08:00)
                if len(start) > 5: start = start[:5]
                if len(end) > 5: end = end[:5]
                
                # Normalize boolean
                is_active = (active == 't' or active == 'true' or active == '1')
                
                schedule[d_id] = {'start': start, 'end': end, 'active': is_active}

    # Analyze Schedule
    # We need to identify which ID is Sunday. Usually 1 or 7.
    # If we have 7 rows, we can infer logic.
    # Pattern matching: If we see 5 days with 08:00-18:00, those are weekdays.
    
    weekdays_correct = 0
    saturday_correct = 0
    sunday_correct = 0
    
    # Logic: Look for the specific patterns regardless of Day ID first
    weekday_pattern_count = 0
    saturday_pattern_count = 0
    sunday_pattern_count = 0
    
    for d_id, data in schedule.items():
        # Check for Mon-Fri pattern (08:00 - 18:00)
        if data['active'] and data['start'] == '08:00' and data['end'] == '18:00':
            weekday_pattern_count += 1
            
        # Check for Saturday pattern (09:00 - 13:00)
        elif data['active'] and data['start'] == '09:00' and data['end'] == '13:00':
            saturday_pattern_count += 1
            
        # Check for Closed (Sunday pattern)
        # Note: Depending on default, other days might be closed if config failed
        elif not data['active']:
            sunday_pattern_count += 1

    # Scoring based on patterns found
    
    # Weekdays: Need 5 days matching 08:00-18:00 (40 pts)
    if weekday_pattern_count == 5:
        score += 40
        feedback_parts.append("Weekdays correctly configured (5 days)")
    elif weekday_pattern_count > 0:
        score += (weekday_pattern_count * 8)
        feedback_parts.append(f"Partial weekdays configured ({weekday_pattern_count}/5)")
    else:
        feedback_parts.append("No weekdays configured correctly")

    # Saturday: Need 1 day matching 09:00-13:00 (20 pts)
    if saturday_pattern_count == 1:
        score += 20
        feedback_parts.append("Saturday correctly configured")
    else:
        feedback_parts.append("Saturday incorrect")

    # Sunday: Need at least 1 closed day (15 pts)
    # Note: If they closed everything, this would pass, but weekdays would fail
    if sunday_pattern_count >= 1:
        score += 15
        feedback_parts.append("Sunday/Non-working day configured")
    else:
        feedback_parts.append("Sunday incorrect (No closed days found)")

    # =========================================================
    # 2. VLM VERIFICATION (Confirm Visuals)
    # =========================================================
    # Visual check is worth 25 points
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of the ManageEngine ServiceDesk Plus Operational Hours configuration.
        I am looking for this specific schedule:
        1. Monday - Friday: 08:00 to 18:00
        2. Saturday: 09:00 to 13:00
        3. Sunday: Unchecked / Greyed out / Not Operational
        
        Answer these questions in JSON format:
        {
            "is_operational_hours_page": true/false,
            "mon_fri_visible_and_correct": true/false,
            "saturday_visible_and_correct": true/false,
            "sunday_closed": true/false
        }
        """
        
        vlm_resp = query_vlm(prompt, images=[final_screenshot])
        
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('is_operational_hours_page'):
                vlm_score += 5
                if parsed.get('mon_fri_visible_and_correct'): vlm_score += 10
                if parsed.get('saturday_visible_and_correct'): vlm_score += 5
                if parsed.get('sunday_closed'): vlm_score += 5
                feedback_parts.append("Visual verification passed")
            else:
                feedback_parts.append("Visual verification: Not on config page")
        else:
            feedback_parts.append("Visual verification failed (VLM error)")
    
    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 70) and (weekday_pattern_count >= 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }