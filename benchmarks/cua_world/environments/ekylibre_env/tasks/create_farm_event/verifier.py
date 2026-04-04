#!/usr/bin/env python3
"""
Verifier for create_farm_event task.
Verifies that a specific calendar event was created in the Ekylibre database.
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_farm_event(traj, env_info, task_info):
    """
    Verify the creation of a farm event.
    
    Scoring Criteria:
    - Event exists (20 pts)
    - Correct Name (10 pts)
    - Correct Start Time (15 pts)
    - Correct End Time (10 pts)
    - Correct Place (10 pts)
    - Correct Description (10 pts)
    - Correct Nature (10 pts)
    - Anti-gaming: Created during task (10 pts)
    - VLM: Visual confirmation of interaction (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Audit certification Agriculture Biologique 2024")
    expected_date = metadata.get('expected_date', "2024-09-20")
    expected_start = metadata.get('expected_start_time', "09:00")
    expected_end = metadata.get('expected_end_time', "12:00")
    expected_place = metadata.get('expected_place_keyword', "GAEC JOULIN")
    expected_desc = metadata.get('expected_desc_keyword', "Ecocert")
    
    # 1. Retrieve result JSON
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
    feedback = []
    
    # Data extraction
    found_event = result.get('found_event')
    latest_event = result.get('latest_event')
    
    # Use found_event if available (name matched), otherwise fallback to latest (check if valid but wrong name)
    event = found_event if found_event else latest_event
    
    # CRITERION 1: Event Existence (20 pts)
    if not event:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No event found in database."
        }
        
    score += 20
    feedback.append("Event record found.")

    # CRITERION 2: Name Accuracy (10 pts)
    name = event.get('name', '')
    if expected_name.lower() in name.lower():
        score += 10
        feedback.append("Name is correct.")
    else:
        feedback.append(f"Name mismatch: '{name}' vs expected '{expected_name}'")

    # CRITERION 3: Start Time (15 pts)
    # format from DB export: YYYY-MM-DD HH:MM:SS
    start_str = event.get('started_at_str', '')
    if expected_date in start_str:
        if expected_start in start_str:
            score += 15
            feedback.append("Start time is correct.")
        else:
            score += 7
            feedback.append(f"Start date correct, but time mismatch ({start_str}).")
    else:
        feedback.append(f"Start date mismatch ({start_str}).")

    # CRITERION 4: End Time (10 pts)
    stop_str = event.get('stopped_at_str', '')
    if expected_date in stop_str:
        if expected_end in stop_str:
            score += 10
            feedback.append("End time is correct.")
        else:
            score += 5
            feedback.append(f"End date correct, but time mismatch ({stop_str}).")
    else:
        feedback.append(f"End date mismatch ({stop_str}).")

    # CRITERION 5: Place (10 pts)
    place = event.get('place', '') or ""
    if expected_place.lower() in place.lower():
        score += 10
        feedback.append("Place is correct.")
    else:
        feedback.append(f"Place mismatch or missing ('{place}').")

    # CRITERION 6: Description (10 pts)
    desc = event.get('description', '') or ""
    if expected_desc.lower() in desc.lower():
        score += 10
        feedback.append("Description contains expected keywords.")
    else:
        feedback.append("Description missing expected keywords.")

    # CRITERION 7: Nature (10 pts)
    nature = event.get('nature', '') or ""
    if "meeting" in nature.lower() or "reunion" in nature.lower() or "réunion" in nature.lower():
        score += 10
        feedback.append("Nature (Meeting) is correct.")
    else:
        feedback.append(f"Nature mismatch ('{nature}').")

    # CRITERION 8: Anti-gaming / Timestamp (10 pts)
    created_at = event.get('created_at_epoch', 0)
    task_start = result.get('task_start_time', 0)
    if created_at > task_start:
        score += 10
        feedback.append("Event verified as created during task session.")
    else:
        feedback.append("Event creation time predates task start (pre-existing record?).")

    # CRITERION 9: VLM Check (5 pts)
    # Simple check if we have trajectory frames, implying agent was active
    # A full VLM check could be added here if the framework supports it
    if len(traj) > 0:
        score += 5
        feedback.append("Trajectory evidence present.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }