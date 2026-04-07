#!/usr/bin/env python3
"""
Verifier for update_appointment_service task.

Verifies:
1. 'Dermatology Consult' service exists and is not voided.
2. Duration is exactly 45 minutes.
3. Description matches target text exactly.
4. Record was modified AFTER task start time (anti-gaming).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_appointment_service(traj, env_info, task_info):
    """
    Verify the appointment service update.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_duration = int(metadata.get('expected_duration', 45))
    expected_description = metadata.get('expected_description', "Comprehensive initial skin assessment and biopsy planning")
    
    # Retrieve result from container
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

    # Extract values
    task_start = result.get('task_start', 0)
    service_exists = result.get('service_exists', False)
    actual_duration = result.get('duration_mins', '0')
    actual_description = result.get('description', '')
    date_changed_ts = result.get('date_changed_ts', 0)

    # Type conversion
    try:
        actual_duration = int(actual_duration)
    except ValueError:
        actual_duration = 0

    score = 0
    max_score = 100
    feedback_parts = []

    # Criterion 1: Service Exists (20 pts)
    if service_exists:
        score += 20
        feedback_parts.append("Service found")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Service 'Dermatology Consult' not found or is voided."
        }

    # Criterion 2: Duration Updated (40 pts)
    if actual_duration == expected_duration:
        score += 40
        feedback_parts.append(f"Duration correct ({actual_duration}m)")
    else:
        feedback_parts.append(f"Duration incorrect (Expected: {expected_duration}, Got: {actual_duration})")

    # Criterion 3: Description Updated (30 pts)
    # We strip whitespace for minor tolerance, but keep case sensitivity as requested
    if actual_description.strip() == expected_description.strip():
        score += 30
        feedback_parts.append("Description correct")
    else:
        # Show a truncated version if too long
        short_actual = (actual_description[:30] + '..') if len(actual_description) > 30 else actual_description
        feedback_parts.append(f"Description mismatch (Got: '{short_actual}')")

    # Criterion 4: Anti-Gaming / Timestamp Check (10 pts)
    # The record must have been changed AFTER the task started
    if date_changed_ts > task_start:
        score += 10
        feedback_parts.append("Modified during task")
    else:
        feedback_parts.append("No modification detected during task session")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }