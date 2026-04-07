#!/usr/bin/env python3
"""
Verifier for batch_assign_homeroom task.

Task: Assign 'Room 101' to Jason Miller, Ashley Davis, and Michael Wilson.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_assign_homeroom(traj, env_info, task_info):
    """
    Verify that the 3 target students were assigned to Room 101.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_room = metadata.get('target_room', 'Room 101')
    
    # 2. Get Result JSON
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

    # 3. Evaluate Results
    students = result.get('students', [])
    if not students:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No student records found in verification data."
        }

    score = 0
    feedback_parts = []
    
    # Scoring: 30 points per student (max 90), +10 for all correct
    correct_count = 0
    total_students = len(students) # Should be 3

    for student in students:
        name = f"{student.get('first_name')} {student.get('last_name')}"
        homeroom = student.get('homeroom', '')
        
        # Check matching (case insensitive and trimming)
        if homeroom and expected_room.lower() in homeroom.lower():
            score += 30
            correct_count += 1
            feedback_parts.append(f"✓ {name}: Assigned to {homeroom}")
        else:
            feedback_parts.append(f"✗ {name}: Current homeroom is '{homeroom}' (Expected: {expected_room})")

    # Bonus for getting all of them
    if correct_count == 3:
        score += 10
        feedback_parts.append("✓ All assignments correct (+10 bonus)")
    
    passed = (correct_count == 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }