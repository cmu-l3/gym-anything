#!/usr/bin/env python3
"""
Verifier for Conditional Room Booking Task.

Logic:
1. Load export result (contains ground truth and agent's event data).
2. Check if agent created an event named "Project Sync".
3. Check if event start time matches target Friday 14:00.
4. Check if event location matches the conditional logic:
   - If Scenario = Blocked -> Location must be "Engineering Lab"
   - If Scenario = Free -> Location must be "Board Room"
"""

import json
import tempfile
import os
import logging
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conditional_room_booking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    ground_truth = data.get('ground_truth', {})
    agent_result = data.get('agent_result', {})
    
    target_date = ground_truth.get('target_date', '')
    expected_location = ground_truth.get('expected_location', '')
    scenario_blocked = ground_truth.get('scenario_blocked', False)
    
    event_found = agent_result.get('found', False)
    actual_location = agent_result.get('location', '').strip()
    actual_start = agent_result.get('start', '')  # Format: YYYY-MM-DD HH:MM:SS

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Event Existence (30 pts)
    if not event_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Event 'Project Sync' was not found in the calendar.",
            "details": data
        }
    
    score += 30
    feedback_parts.append("Event 'Project Sync' created")

    # 2. Time Verification (20 pts)
    # Check that date matches target_date and time is 14:00
    # Odoo stores in UTC. If the environment is set to UTC, 14:00 is 14:00.
    # However, if user input 2PM local, and local is not UTC, this might vary.
    # Standard Odoo docker images often default to UTC. 
    # The setup script created the blocking event at "14:00:00" string literal.
    # We expect the agent to match that.
    
    time_correct = False
    if target_date in actual_start and "14:00" in actual_start:
        time_correct = True
        score += 20
        feedback_parts.append(f"Correct time ({target_date} 14:00)")
    else:
        feedback_parts.append(f"Incorrect time: {actual_start} (Expected {target_date} 14:00)")

    # 3. Location/Conditional Verification (50 pts)
    # The core of the task is the condition.
    
    loc_correct = False
    # Case-insensitive comparison
    if actual_location.lower() == expected_location.lower():
        loc_correct = True
        score += 50
        feedback_parts.append(f"Correct conditional location: '{actual_location}'")
    else:
        scenario_str = "BLOCKED" if scenario_blocked else "FREE"
        feedback_parts.append(f"Wrong location for {scenario_str} scenario. Found: '{actual_location}', Expected: '{expected_location}'")

    # Final Pass Determination
    # Must get location right to pass (it's the main point)
    # Must get time roughly right
    passed = loc_correct and time_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "scenario_blocked": scenario_blocked,
            "expected": expected_location,
            "found": actual_location,
            "event_time": actual_start
        }
    }