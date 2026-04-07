#!/usr/bin/env python3
"""
Verifier for the OpenProject Refactor and Split Task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_refactor_and_split(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Renamed the original work package to "Implement product search (Backend)".
    2. Set the original WP estimate to 24h.
    3. Created a new WP "Implement product search (Frontend)" with 16h estimate.
    4. Assigned the new WP to Alice Johnson.
    5. Linked the two WPs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values
    EXPECTED_BACKEND_SUBJECT = "Implement product search (Backend)"
    EXPECTED_FRONTEND_SUBJECT = "Implement product search (Frontend)"
    EXPECTED_BACKEND_ESTIMATE = 24.0
    EXPECTED_FRONTEND_ESTIMATE = 16.0
    EXPECTED_ASSIGNEE = "Alice Johnson"

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result_final.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize score
    score = 0
    feedback = []
    
    # Check 1: Original WP Modifications (40 pts)
    original_wp = result.get('original_wp')
    if original_wp:
        # Subject Check (20 pts)
        actual_subject = original_wp.get('subject', '').strip()
        if EXPECTED_BACKEND_SUBJECT.lower() in actual_subject.lower():
            score += 20
            feedback.append("Original task renamed correctly.")
        else:
            feedback.append(f"Original task subject incorrect. Expected '{EXPECTED_BACKEND_SUBJECT}', got '{actual_subject}'.")

        # Estimate Check (20 pts)
        actual_est = original_wp.get('estimated_hours')
        if actual_est is not None and abs(float(actual_est) - EXPECTED_BACKEND_ESTIMATE) < 0.1:
            score += 20
            feedback.append("Original task estimate updated to 24h.")
        else:
            feedback.append(f"Original task estimate incorrect. Expected {EXPECTED_BACKEND_ESTIMATE}, got {actual_est}.")
    else:
        feedback.append("Could not find original work package (Critical Failure).")

    # Check 2: New WP Creation (40 pts)
    new_wp = result.get('new_wp')
    if new_wp:
        # Existence implies creation (10 pts)
        score += 10
        feedback.append("New Frontend task created.")

        # Estimate Check (10 pts)
        actual_new_est = new_wp.get('estimated_hours')
        if actual_new_est is not None and abs(float(actual_new_est) - EXPECTED_FRONTEND_ESTIMATE) < 0.1:
            score += 10
            feedback.append("New task estimate set to 16h.")
        else:
            feedback.append(f"New task estimate incorrect. Expected {EXPECTED_FRONTEND_ESTIMATE}, got {actual_new_est}.")

        # Assignee Check (10 pts)
        actual_assignee = new_wp.get('assignee', '')
        if actual_assignee and EXPECTED_ASSIGNEE.lower() in actual_assignee.lower():
            score += 10
            feedback.append("New task assigned to Alice Johnson.")
        else:
            feedback.append(f"New task assignee incorrect. Expected '{EXPECTED_ASSIGNEE}', got '{actual_assignee}'.")
            
        # Subject Exact Match Bonus (10 pts)
        if new_wp.get('subject', '').strip() == EXPECTED_FRONTEND_SUBJECT:
            score += 10
            feedback.append("New task subject matches exactly.")
        else:
            feedback.append(f"New task subject close but not exact. Got: '{new_wp.get('subject')}'")

    else:
        feedback.append("New 'Frontend' task was not found or not created during the task window.")

    # Check 3: Relationship (20 pts)
    if result.get('relation_exists'):
        score += 20
        feedback.append("Tasks successfully linked.")
    else:
        feedback.append("No link found between the Backend and Frontend tasks.")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }