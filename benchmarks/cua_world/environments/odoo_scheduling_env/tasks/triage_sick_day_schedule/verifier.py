#!/usr/bin/env python3
"""
Verifier for Triage Sick Day Schedule task.
"""

import json
import os
import tempfile
from datetime import datetime, timedelta

def verify_triage_sick_day_schedule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result from container
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
    
    target_monday_str = result.get("target_monday", "")
    if not target_monday_str:
        return {"passed": False, "score": 0, "feedback": "System error: Target date not found in result"}

    try:
        target_monday = datetime.strptime(target_monday_str, "%Y-%m-%d").date()
    except ValueError:
        return {"passed": False, "score": 0, "feedback": "System error: Invalid target date format"}

    # 1. Verify "One-on-One with Mentor" is deleted (20 pts)
    if not result["one_on_one"]["exists"]:
        score += 20
        feedback.append("One-on-One deleted successfully.")
    else:
        feedback.append("One-on-One meeting still exists (fail).")

    # 2. Verify "Q2 Financial Review" rescheduled to Friday (30 pts + 10 pts attr)
    review = result["review"]
    if review["exists"]:
        # Check date
        start_str = review["start"] # Format: YYYY-MM-DD HH:MM:SS
        try:
            start_dt = datetime.strptime(start_str, "%Y-%m-%d %H:%M:%S")
            # Expected: Friday of the same week as target_monday
            # Monday is day 0, Friday is day 4. So +4 days.
            expected_friday = target_monday + timedelta(days=4)
            
            if start_dt.date() == expected_friday:
                score += 30
                feedback.append("Q2 Review rescheduled to correct Friday.")
            else:
                feedback.append(f"Q2 Review on wrong day: {start_dt.date()} (expected {expected_friday}).")
            
            # Check time (should be 10:00:00)
            if start_dt.hour == 10 and start_dt.minute == 0:
                # Time check implicit in high score, but good to note
                pass
            else:
                feedback.append(f"Q2 Review time changed (expected 10:00, got {start_dt.time()}).")
                
            # Check Duration (should be 1.5)
            if abs(review["duration"] - 1.5) < 0.1:
                score += 10
                feedback.append("Q2 Review duration preserved.")
            else:
                feedback.append("Q2 Review duration altered.")

        except ValueError:
            feedback.append("Error parsing Q2 start time.")
    else:
        feedback.append("Q2 Review meeting deleted (fail).")

    # 3. Verify "Team Standup" modifications (10 pts exists, 20 pts Alice removed, 10 pts others kept)
    standup = result["standup"]
    if standup["exists"]:
        score += 10
        attendees = standup["attendees"]
        
        # Check Alice removed
        if "Alice Johnson" not in attendees:
            score += 20
            feedback.append("Alice removed from Standup.")
        else:
            feedback.append("Alice still in Standup (fail).")
            
        # Check others kept (Carol and David)
        others_present = any("Carol" in a for a in attendees) and any("David" in a for a in attendees)
        if others_present:
            score += 10
            feedback.append("Other attendees preserved in Standup.")
        else:
            feedback.append("Other attendees missing from Standup.")
    else:
        feedback.append("Team Standup meeting deleted (fail).")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }