#!/usr/bin/env python3
"""
Verifier for schedule_and_activate_exam task.

Checks that:
1. Exam 'CS101 - Algorithms Final' exists in the database.
2. Status has been changed to Active/Published.
3. Valid From/Start Date is accurately scheduled to 2026-05-20 08:45.
4. Valid To/End Date is accurately scheduled to 2026-05-20 12:00.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_and_activate_exam(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    exam_details = result.get('exam_details', {})
    config_details = result.get('config_details', {})

    # Use whatever details block is populated and has our expected changes
    details = {}
    if exam_details and config_details:
        # We determine which one the agent modified by checking for the target year
        if '2026' in str(exam_details):
            details = exam_details
        else:
            details = config_details
    else:
        details = exam_details if exam_details else config_details

    if not details:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Exam/Config 'CS101 - Algorithms Final' not found or contains no configuration details."
        }

    # Criterion 1: Status check (30 pts)
    status = str(details.get('status', '')).upper()
    active = str(details.get('active', '')).upper()
    
    is_active = False
    if status in ['ACTIVE', 'PUBLISHED', '1', 'TRUE']:
        is_active = True
    if active in ['1', 'TRUE', 'ACTIVE']:
        is_active = True
        
    if is_active:
        score += 30
        feedback.append("Exam status set to Active")
    else:
        feedback.append(f"Exam status is not active (status={status}, active={active})")

    # Criterion 2: Start Date and Time Check (35 pts)
    valid_from = str(details.get('valid_from', ''))
    start_time = str(details.get('start_time', ''))
    start_str = valid_from if valid_from and valid_from != 'None' else start_time

    if '2026-05-20' in start_str:
        score += 20
        feedback.append("Start Date correct")
    else:
        feedback.append(f"Start Date incorrect (Found: {start_str})")

    if '08:45' in start_str:
        score += 15
        feedback.append("Start Time correct")
    else:
        feedback.append(f"Start Time incorrect (Found: {start_str})")

    # Criterion 3: End Date and Time Check (35 pts)
    valid_to = str(details.get('valid_to', ''))
    end_time = str(details.get('end_time', ''))
    end_str = valid_to if valid_to and valid_to != 'None' else end_time

    if '2026-05-20' in end_str:
        score += 20
        feedback.append("End Date correct")
    else:
        feedback.append(f"End Date incorrect (Found: {end_str})")

    if '12:00' in end_str:
        score += 15
        feedback.append("End Time correct")
    else:
        feedback.append(f"End Time incorrect (Found: {end_str})")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": details
    }