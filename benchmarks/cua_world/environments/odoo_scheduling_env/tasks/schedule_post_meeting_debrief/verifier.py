#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime, timedelta

def verify_schedule_post_meeting_debrief(traj, env_info, task_info):
    """
    Verifies that the 'Debrief' meeting was scheduled exactly 30 minutes after
    the 'Investor Update Preparation' meeting.
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
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    # Extract Data
    ref_event = result.get('reference_event')
    target_events = result.get('target_events', [])

    # 1. Verify Reference Event Exists (Sanity Check)
    if not ref_event:
        return {"passed": False, "score": 0, "feedback": "Reference event 'Investor Update Preparation' disappeared from DB."}

    # 2. Verify Target Event Exists
    if not target_events:
        return {"passed": False, "score": 0, "feedback": "No event named 'Debrief' was found."}

    # If multiple 'Debrief' events found, pick the most recently modified one
    # (though setup script clears them, so there should be only one)
    debrief = sorted(target_events, key=lambda x: x['write_date'], reverse=True)[0]

    # Scoring Logic
    score = 0
    feedback = []

    # Criterion: Event Created (20 pts)
    score += 20
    feedback.append("'Debrief' event created.")

    # Parse Datetimes (Odoo format: "YYYY-MM-DD HH:MM:SS")
    fmt = "%Y-%m-%d %H:%M:%S"
    try:
        ref_stop = datetime.strptime(ref_event['stop'], fmt)
        deb_start = datetime.strptime(debrief['start'], fmt)
        deb_stop = datetime.strptime(debrief['stop'], fmt)
    except ValueError:
        return {"passed": False, "score": score, "feedback": "Date parsing failed (internal error)."}

    # Criterion: Correct Date (20 pts)
    if ref_stop.date() == deb_start.date():
        score += 20
        feedback.append("Correct date.")
    else:
        feedback.append(f"Wrong date. Expected {ref_stop.date()}, got {deb_start.date()}.")

    # Criterion: 30 Minute Gap (40 pts)
    # Odoo stores in UTC, so direct subtraction works
    diff = (deb_start - ref_stop).total_seconds() / 60
    
    if abs(diff - 30.0) < 1.0: # 1 minute tolerance
        score += 40
        feedback.append("Start time is exactly 30 mins after reference.")
    else:
        feedback.append(f"Wrong start time. Gap is {diff:.1f} mins (expected 30).")

    # Criterion: 30 Minute Duration (20 pts)
    duration = (deb_stop - deb_start).total_seconds() / 60
    if abs(duration - 30.0) < 1.0:
        score += 20
        feedback.append("Duration is 30 mins.")
    else:
        feedback.append(f"Wrong duration. Duration is {duration:.1f} mins (expected 30).")

    passed = score >= 100  # Strict pass for scheduling precision
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }