#!/usr/bin/env python3
import json
import datetime
import os
import tempfile

def verify_optimize_meeting_schedule(traj, env_info, task_info):
    """
    Verifies that the Q2 Financial Review meeting was moved to start immediately
    after Team Standup and that the location was updated.
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

    # Check for basic data existence
    standup = result.get("team_standup")
    review = result.get("financial_review")
    error = result.get("error")

    if error:
        return {"passed": False, "score": 0, "feedback": f"Error querying database: {error}"}
    
    if not standup:
        return {"passed": False, "score": 0, "feedback": "Team Standup event not found. It should not have been deleted."}
    
    if not review:
        return {"passed": False, "score": 0, "feedback": "Q2 Financial Review event not found."}

    # Helpers
    fmt = '%Y-%m-%d %H:%M:%S'
    def parse_dt(dt_str):
        return datetime.datetime.strptime(dt_str, fmt)

    score = 0
    feedback_parts = []
    
    # 1. Reference Event Stability (10 pts)
    # Team Standup should still start at 09:00 (checking minutes/seconds mostly)
    # We verify it hasn't been moved significantly
    standup_start = parse_dt(standup['start'])
    standup_stop = parse_dt(standup['stop'])
    
    # Verify Standup duration is still 30 mins
    standup_duration = (standup_stop - standup_start).total_seconds() / 60
    if abs(standup_duration - 30) < 1:
        score += 10
        feedback_parts.append("Reference event 'Team Standup' intact.")
    else:
        feedback_parts.append(f"Reference event modified (duration {standup_duration}m).")

    # 2. Gap Elimination (40 pts)
    # Review Start should equal Standup Stop
    review_start = parse_dt(review['start'])
    
    gap_seconds = (review_start - standup_stop).total_seconds()
    
    if abs(gap_seconds) < 60: # Allow 1 minute tolerance
        score += 40
        feedback_parts.append("Gap eliminated successfully.")
    else:
        gap_minutes = gap_seconds / 60
        feedback_parts.append(f"Gap not eliminated. Time difference is {gap_minutes} minutes.")

    # 3. Location Consolidation (30 pts)
    # Review Location should be 'Main Conference Room'
    target_location = "Main Conference Room"
    actual_location = review.get('location', '') or ""
    
    # Odoo location might be a string or related field, read returns string usually for char fields
    if target_location.lower() in str(actual_location).lower():
        score += 30
        feedback_parts.append("Location correctly updated to Main Conference Room.")
    else:
        feedback_parts.append(f"Location incorrect. Expected '{target_location}', got '{actual_location}'.")

    # 4. Duration Preservation (20 pts)
    # Review duration should be 90 minutes
    review_stop = parse_dt(review['stop'])
    review_duration = (review_stop - review_start).total_seconds() / 60
    
    if abs(review_duration - 90) < 2: # 2 min tolerance
        score += 20
        feedback_parts.append("Duration preserved (90 mins).")
    else:
        feedback_parts.append(f"Duration incorrect. Expected 90m, got {review_duration}m.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }