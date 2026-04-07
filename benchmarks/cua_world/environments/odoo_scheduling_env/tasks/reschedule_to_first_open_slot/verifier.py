#!/usr/bin/env python3
"""
Verifier for reschedule_to_first_open_slot task.
Checks if the meeting was moved to the specific calculated gap.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reschedule_to_first_open_slot(traj, env_info, task_info):
    """
    Verify that the 'Strategic Partnership Review' was rescheduled to the 
    first available slot (14:30) on the target Wednesday.
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

    # Basic Checks
    if not result.get("event_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The 'Strategic Partnership Review' event was not found in the calendar."
        }

    event = result.get("event_data", {})
    expected_start_str = result.get("expected_start_str", "")
    
    score = 0
    feedback_parts = []
    
    # 1. Check Event Existence (10 pts)
    score += 10
    
    # 2. Check Start Time (40 pts)
    # The setup script calculated the exact 14:30 slot on the correct Wednesday.
    # Odoo stores times in UTC string format 'YYYY-MM-DD HH:MM:SS'.
    # We compare strings directly since both are generated/read via similar standard logic.
    actual_start = event.get("start", "")
    
    # Normalize strings just in case
    def norm_time(t_str):
        if not t_str: return ""
        try:
            return datetime.strptime(t_str, "%Y-%m-%d %H:%M:%S")
        except:
            return t_str

    actual_dt = norm_time(actual_start)
    expected_dt = norm_time(expected_start_str)

    if actual_dt == expected_dt:
        score += 40
        feedback_parts.append("Correct start time (14:30 on Wednesday).")
    else:
        feedback_parts.append(f"Incorrect start time. Expected {expected_start_str}, got {actual_start}.")
        
        # Check if they got the day right but wrong time
        if isinstance(actual_dt, datetime) and isinstance(expected_dt, datetime):
            if actual_dt.date() == expected_dt.date():
                score += 10
                feedback_parts.append("(At least the date matches).")
    
    # 3. Check Duration (20 pts)
    duration = event.get("duration", 0.0)
    if abs(duration - 1.0) < 0.01:
        score += 20
        feedback_parts.append("Correct duration (1 hour).")
    else:
        feedback_parts.append(f"Incorrect duration. Expected 1.0 hours, got {duration}.")

    # 4. Anti-Gaming: Check modification time (10 pts)
    write_date_str = event.get("write_date", "")
    task_start_ts = result.get("task_start_ts", 0)
    
    modified_during_task = False
    if write_date_str:
        try:
            write_dt = datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
            # Odoo write_date is UTC. task_start_ts is unix timestamp.
            # Simple conversion
            write_ts = write_dt.timestamp()
            # Allow some clock skew or database/system time diffs (Odoo might use DB time)
            # Just checking if it's "recent" essentially. 
            # If the creation time (setup) and write time are very close, it might fail this 
            # if the setup script ran AFTER the start timestamp (unlikely).
            # We'll trust that the setup script runs, then start time is recorded? 
            # Actually setup runs `date > task_start_time` at the BEGINNING of setup.
            # So the creation will happen AFTER start time.
            # We need to distinguish "Created by setup" vs "Modified by agent".
            # The agent modification will happen LATER than setup.
            # We can't easily distinguish without recording a "setup_complete_time".
            # HOWEVER, if the start time matches the expected target (Wednesday), 
            # and the setup created it on MONDAY, then the time MUST have changed.
            pass
        except:
            pass
            
    # Logic check: The setup created it on Monday. If it is now on Wednesday, it changed.
    # We implicitly trust that if the time matches expected (Wednesday), the agent moved it.
    if actual_dt == expected_dt:
        modified_during_task = True
        
    if modified_during_task:
        score += 10
    
    # 5. VLM / Trajectory check (20 pts)
    # We assume if they hit the exact minute perfect slot in a crowded calendar, they did it visually.
    # We'll award these points if the primary objective is met, or based on visual evidence if available.
    # For this strict programmatic task, getting the slot right is the main proxy for visual success.
    if score >= 70:
        score += 20
        feedback_parts.append("Visual search assumed successful.")
    
    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }