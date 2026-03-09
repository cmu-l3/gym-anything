#!/usr/bin/env python3
"""
Verifier for block_schedule_meeting task.

Verifies that the agent successfully blocked off time in the schedule.
"""

import json
import logging
import os
import sys
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_time(t_str):
    """Parse time string HH:MM:SS to datetime object."""
    try:
        return datetime.strptime(t_str, "%H:%M:%S")
    except ValueError:
        return None

def verify_block_schedule_meeting(traj, env_info, task_info):
    """
    Verify the schedule block task.
    
    Criteria:
    1. Entry exists on the correct date (active, not cancelled).
    2. Start time matches 13:00:00.
    3. End time matches 16:00:00 OR duration is 180 (minutes).
    4. Text contains 'Strategy Meeting'.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_start = metadata.get('start_time', '13:00:00')
    target_end = metadata.get('end_time', '16:00:00')
    required_text = metadata.get('required_text', 'Strategy Meeting')

    score = 0
    feedback_parts = []
    
    entries = result.get('entries', [])
    
    if not entries:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No active appointment/block found on the target date (2026-03-20)."
        }
    
    # Check each entry to find the best match
    best_match_score = 0
    best_match_feedback = []
    
    for entry in entries:
        current_score = 0
        current_feedback = []
        
        # 1. Entry exists (Base points)
        current_score += 15
        current_feedback.append("Entry created on target date")
        
        # 2. Check Start Time
        # Handle variations like 13:00 vs 13:00:00
        start_t = entry.get('start_time', '')
        if start_t.startswith('13:00'):
            current_score += 25
            current_feedback.append("Correct start time (13:00)")
        else:
            current_feedback.append(f"Incorrect start time: {start_t}")

        # 3. Check End Time / Duration
        end_t = entry.get('end_time', '')
        duration = str(entry.get('duration', '0'))
        
        # Duration is often in seconds or minutes depending on schema, usually minutes in OSCAR view but seconds in DB?
        # Standard OSCAR 'duration' column is often in seconds. 3 hours = 10800 seconds. 
        # Or sometimes minutes = 180.
        # We'll check end time string first as it's more reliable if populated.
        
        if end_t.startswith('16:00'):
            current_score += 20
            current_feedback.append("Correct end time (16:00)")
        elif duration in ['10800', '180']: # Check both seconds and minutes just in case
            current_score += 20
            current_feedback.append("Correct duration (3 hours)")
        else:
            # Calculate from start/end if possible
            s_obj = parse_time(start_t)
            e_obj = parse_time(end_t)
            if s_obj and e_obj:
                diff = (e_obj - s_obj).total_seconds()
                if diff == 10800: # 3 * 60 * 60
                    current_score += 20
                    current_feedback.append("Correct calculated duration")
                else:
                    current_feedback.append(f"Incorrect duration/end time: {end_t} (diff={diff}s)")
            else:
                current_feedback.append(f"Incorrect end time: {end_t}")

        # 4. Check Text
        reason = entry.get('reason', '') or ''
        notes = entry.get('notes', '') or ''
        full_text = (reason + " " + notes).lower()
        
        if "strategy meeting" in full_text:
            current_score += 20
            current_feedback.append("Correct reason text found")
        elif "meeting" in full_text:
            current_score += 10
            current_feedback.append("Partial reason text found ('meeting')")
        else:
            current_feedback.append(f"Reason text missing required '{required_text}'")

        # 5. Active Status (Bonus/Confirmation)
        # Query filtered by status != 'C', so if it's here, it's active.
        current_score += 20
        
        if current_score > best_match_score:
            best_match_score = current_score
            best_match_feedback = current_feedback

    # VLM Verification (Bonus/Anti-gaming)
    # If we have a good programmatic score, we assume success, but we could check trajectory
    # to ensure they didn't just SQL inject (unlikely given the environment constraints, but good practice).
    # For now, we rely on the programmatic check of the DB result.
    
    passed = best_match_score >= 75
    
    return {
        "passed": passed,
        "score": best_match_score,
        "feedback": " | ".join(best_match_feedback)
    }