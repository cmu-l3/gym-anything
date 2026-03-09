#!/usr/bin/env python3
"""
Verifier for add_flight_authorization task.

Verifies that the agent created a Flight Authorization in Aerobridge with:
- Correct Title
- Correct Max Height (400) & Ceiling (500)
- Correct Dates
- Correct boolean flags (No crowd permit)
- Linked Operator

Scoring is based on 100 points total.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_flight_authorization(traj, env_info, task_info):
    """
    Verify the creation of the flight authorization record.
    """
    # 1. Setup and retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_title_part = "Mumbai Port Area BVLOS"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Results
    score = 0
    feedback_parts = []
    
    count_before = result.get('count_before', 0)
    current_count = result.get('current_count', 0)
    record_found = result.get('record_found', False)
    record = result.get('record', {})
    
    # CRITERION 1: Record Creation (20 pts)
    # Did the count increase?
    if current_count > count_before:
        score += 20
        feedback_parts.append("✓ New Authorization record created (+20)")
    else:
        feedback_parts.append("✗ No new Authorization record created")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No record created. " + " ".join(feedback_parts)
        }

    # CRITERION 2: Title Match (20 pts)
    # Only checked if record_found is True (which implies title match in export script)
    if record_found:
        title = record.get('title', '')
        if expected_title_part.lower() in title.lower():
            score += 20
            feedback_parts.append(f"✓ Title correct ('{title}') (+20)")
        else:
            feedback_parts.append(f"✗ Title mismatch. Got: '{title}'")
    else:
        # If count increased but record not found, they likely used wrong title
        latest_title = result.get('latest_record_title', 'Unknown')
        feedback_parts.append(f"✗ Record created but title incorrect. Got: '{latest_title}'")
        # Exit early if main record not identified
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # CRITERION 3: Height and Ceiling (20 pts)
    height = record.get('operation_max_height')
    ceiling = record.get('operation_ceiling')
    
    if height == 400:
        score += 10
        feedback_parts.append("✓ Max Height 400 correct (+10)")
    else:
        feedback_parts.append(f"✗ Max Height incorrect (Expected 400, got {height})")
        
    if ceiling == 500:
        score += 10
        feedback_parts.append("✓ Ceiling 500 correct (+10)")
    else:
        feedback_parts.append(f"✗ Ceiling incorrect (Expected 500, got {ceiling})")

    # CRITERION 4: Dates (10 pts)
    start_date = record.get('start_date')
    end_date = record.get('end_date')
    
    if start_date and "2024-06-01" in start_date:
        score += 5
        feedback_parts.append("✓ Start Date correct (+5)")
    else:
        feedback_parts.append(f"✗ Start Date incorrect (Expected 2024-06-01..., got {start_date})")

    if end_date and "2024-12-31" in end_date:
        score += 5
        feedback_parts.append("✓ End Date correct (+5)")
    else:
        feedback_parts.append(f"✗ End Date incorrect (Expected 2024-12-31..., got {end_date})")

    # CRITERION 5: Crowd Permit (10 pts)
    # Expected: False (Unchecked)
    crowd_permit = record.get('permit_to_fly_above_crowd')
    if crowd_permit is False:
        score += 10
        feedback_parts.append("✓ Crowd Permit 'No' correct (+10)")
    else:
        feedback_parts.append(f"✗ Crowd Permit incorrect (Expected False/No, got {crowd_permit})")

    # CRITERION 6: Operator Linked (10 pts)
    # Operator ID should not be None
    if record.get('operator_id'):
        score += 10
        feedback_parts.append("✓ Operator linked (+10)")
    else:
        feedback_parts.append("✗ No Operator selected")

    # CRITERION 7: VLM Trajectory Check (10 pts)
    # Verify that the agent actually interacted with the form
    # (Simple check: did they navigate and spend steps?)
    # Since we have strong programmatic verification, this is a bonus/sanity check
    if len(traj) > 2:
        score += 10
        feedback_parts.append("✓ Workflow trajectory valid (+10)")
    else:
        feedback_parts.append("? Trajectory too short")

    # Final Result
    passed = (score >= 60) and record_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }