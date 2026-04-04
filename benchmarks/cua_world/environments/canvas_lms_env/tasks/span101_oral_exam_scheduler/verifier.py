#!/usr/bin/env python3
"""
Verifier for SPAN101 Oral Exam Scheduler task.

Verifies that:
1. An appointment group exists for SPAN101.
2. Configuration matches requirements (Title, Location, Duration, Limit).
3. The group is published (active) and has slots generated.
4. The group was created during the task window.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_span101_oral_exam_scheduler(traj, env_info, task_info):
    """
    Verify the appointment group creation.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    group_found = result.get("group_found", False)
    group_data = result.get("group", {})
    slots_created = result.get("slots_created", False)
    task_start = result.get("task_start_time", 0)
    created_at = group_data.get("created_at", 0)

    score = 0
    feedback = []

    # Criterion 1: Group Created & Active (20 pts)
    if group_found and group_data.get("workflow_state") == 'active':
        score += 20
        feedback.append("Active appointment group found")
    else:
        feedback.append("No active appointment group found for SPAN101")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Anti-gaming: Timestamp check
    if created_at < task_start:
        feedback.append("Group created before task started (stale data)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    
    # Criterion 2: Title & Location (20 pts)
    title = group_data.get("title", "")
    location = group_data.get("location", "")
    
    if "Oral Proficiency Exams" in title:
        score += 10
        feedback.append("Title correct")
    else:
        feedback.append(f"Title mismatch: '{title}'")
        
    if "Language Lab 101" in location:
        score += 10
        feedback.append("Location correct")
    else:
        feedback.append(f"Location mismatch: '{location}'")

    # Criterion 3: Duration Config (20 pts)
    duration = int(group_data.get("duration_minutes", 0))
    if duration == 15:
        score += 20
        feedback.append("Duration correct (15 min)")
    else:
        feedback.append(f"Duration incorrect: {duration} min")

    # Criterion 4: Participant Limit (20 pts)
    # This is critical for oral exams (one-on-one)
    limit = int(group_data.get("participants_limit", 0))
    if limit == 1:
        score += 20
        feedback.append("Participant limit correct (1)")
    else:
        feedback.append(f"Participant limit incorrect: {limit}")

    # Criterion 5: Slots Generated (20 pts)
    if slots_created:
        score += 20
        feedback.append("Appointment slots generated successfully")
    else:
        feedback.append("No time slots generated (did you add the date/time range?)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }