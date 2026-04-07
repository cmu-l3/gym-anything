#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_part_time_transition(traj, env_info, task_info):
    """
    Verifies that:
    1. Audrey Peterson's schedule is set to "Part Time 20 Hours".
    2. A log note was added with required keywords.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    target_schedule = metadata.get('target_schedule', "Part Time 20 Hours")
    required_fragments = metadata.get('required_note_fragments', ["part-time", "effective"])

    # Copy result file
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

    score = 0
    feedback_parts = []
    
    # Check 1: Employee Found (10 pts)
    if result.get("employee_found"):
        score += 10
    else:
        return {"passed": False, "score": 0, "feedback": "Employee Audrey Peterson not found in database."}

    # Check 2: Schedule Updated (40 pts)
    current_schedule = result.get("current_schedule", "")
    if current_schedule == target_schedule:
        score += 40
        feedback_parts.append(f"Schedule correctly updated to '{target_schedule}'.")
    else:
        feedback_parts.append(f"Incorrect schedule: found '{current_schedule}', expected '{target_schedule}'.")

    # Check 3: Log Note Existence & Content (50 pts total)
    log_notes = result.get("log_notes", [])
    note_found = False
    content_valid = False
    
    for note in log_notes:
        body = note.get("body", "").lower()
        # Odoo stores body as HTML (e.g., <p>Text</p>), so simple substring search works
        if any(frag in body for frag in required_fragments):
            note_found = True
            # Check for ALL fragments for full points
            if all(frag in body for frag in required_fragments):
                content_valid = True
            break
            
    if note_found:
        score += 30
        feedback_parts.append("Log note found.")
        if content_valid:
            score += 20
            feedback_parts.append("Log note content matches requirements.")
        else:
            feedback_parts.append(f"Log note found but missing some keywords (required: {required_fragments}).")
    else:
        feedback_parts.append("No log note found with required text.")

    # Final verdict
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }