#!/usr/bin/env python3
"""
Verifier for schedule_irregular_training_series task.
Checks if 3 specific calendar events were created with correct details.
"""

import json
import logging
import datetime
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_irregular_training_series(traj, env_info, task_info):
    """
    Verify the agent created 3 'Leadership 101' events matching the schedule.
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

    # Check for script errors
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error querying Odoo: {result['error']}"}

    events = result.get("events_found", [])
    ground_truth = result.get("ground_truth", [])
    file_accessed = result.get("file_accessed", False)

    score = 0
    feedback = []

    # 1. Verification Logic
    # We need to match found events to ground truth sessions.
    # Since Odoo stores UTC and setup calculated local dates, we match primarily on:
    # - Day of month
    # - Hour (approximate, allowing for timezone shift if env is not UTC, but typically
    #   in these envs, if user inputs 10:00, DB stores something relative to that.
    #   The most robust check is looking for an event that starts within the expected hour block).
    
    # Let's assume the agent entered the times exactly as requested.
    # Ground truth has 'start_hour' (e.g. 10 for 10:00 AM).
    # We look for an event on that specific date where the start time's hour matches.
    # Note: Odoo 'start' field is a string "YYYY-MM-DD HH:MM:SS".
    
    matched_sessions = 0
    
    for session in ground_truth:
        sess_iso = session["iso_date"] # YYYY-MM-DD
        sess_hour = session["start_hour"]
        
        # Find a matching event
        match = None
        for event in events:
            # Parse Odoo date
            # event['start'] format: "2023-10-27 10:00:00"
            try:
                evt_start_dt = datetime.datetime.strptime(event['start'], "%Y-%m-%d %H:%M:%S")
                evt_date_str = evt_start_dt.date().isoformat()
                
                # Check date match
                if evt_date_str == sess_iso:
                    # Check time match (Hour)
                    # We allow strict matching. If env is UTC and agent inputs 10:00 AM local, 
                    # it might shift. However, in this controlled env, usually 10=10.
                    # If verification fails often due to TZ, relax this.
                    if evt_start_dt.hour == sess_hour:
                        match = event
                        break
            except Exception as e:
                logger.warning(f"Error parsing event date: {e}")
                continue
        
        if match:
            matched_sessions += 1
            session_score = 20 # Base points for creating the session on right day/time
            
            # Check details
            details_correct = True
            
            # Location
            loc = match.get('location', '') or ''
            if "Board Room" in loc:
                session_score += 3.33 # 10 pts total split by 3
            else:
                feedback.append(f"Session {sess_iso}: Incorrect location '{loc}'")
                details_correct = False
                
            # Description
            desc = match.get('description', '') or ''
            if "Core leadership principles" in desc:
                session_score += 3.33
            else:
                feedback.append(f"Session {sess_iso}: Description missing or incorrect")
                details_correct = False

            # Attendees
            # Expect Alice Johnson and Frank Rivera
            attendees = match.get('attendee_names', [])
            has_alice = any("Alice Johnson" in a for a in attendees)
            has_frank = any("Frank Rivera" in a for a in attendees)
            
            if has_alice and has_frank:
                session_score += 3.33
            else:
                feedback.append(f"Session {sess_iso}: Missing required attendees (Found: {attendees})")
                details_correct = False
            
            # Recurrence check
            # We want individual events, NOT recurrence
            if match.get('recurrency'):
                feedback.append(f"Session {sess_iso}: Used recurrence (should be individual event)")
                session_score -= 5 # Penalty for using recurrence
            else:
                session_score += 3.33 # 10 pts total for no recurrence
                
            score += session_score
            # Remove match to prevent double counting
            events.remove(match)
        else:
            feedback.append(f"Missing session for {sess_iso} at {sess_hour}:00")

    # Clean up floating point scores
    score = min(100, round(score))
    
    # File access check (Anti-gaming / Process check)
    if not file_accessed:
        feedback.append("Warning: Schedule text file was not accessed.")
        # We don't penalize heavily if they got it right (maybe they guessed?), 
        # but typically this implies gaming or previous knowledge.
        if score > 0:
            score -= 5

    passed = (matched_sessions == 3) and (score >= 70)

    if matched_sessions == 3:
        feedback.append("All 3 sessions created on correct dates/times.")
    else:
        feedback.append(f"Only {matched_sessions}/3 sessions found.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }