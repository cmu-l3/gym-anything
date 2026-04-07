#!/usr/bin/env python3
"""
Verifier for move_work_package_cross_project task.
Verifies that the specified work package was moved (not copied) to the correct project.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_move_work_package(traj, env_info, task_info):
    """
    Verify the work package move.
    
    Criteria:
    1. Work package "Set up application monitoring and alerting" exists (Critical)
    2. Work package is in "mobile-banking-app" project (60 pts)
    3. Work package is NOT in "devops-automation" project (10 pts)
    4. Exact subject match (15 pts)
    5. Single instance exists (implies move not copy) (15 pts)
    6. Anti-gaming: State actually changed from initial
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_project = metadata.get('target_project_identifier', 'mobile-banking-app')
    source_project = metadata.get('source_project_identifier', 'devops-automation')
    expected_subject = metadata.get('wp_subject', 'Set up application monitoring and alerting')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract states
    initial_state = result.get('initial_state', {})
    final_state = result.get('final_state', {})
    
    feedback_parts = []
    score = 0
    
    # Check if we got valid DB data
    if final_state.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Database query error: {final_state.get('error')}"}

    final_count = final_state.get('count', 0)
    work_packages = final_state.get('work_packages', [])

    # CRITERION 1: Work package found
    if final_count == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: The work package 'Set up application monitoring and alerting' was not found. It may have been deleted."
        }
    
    # We examine the first WP found (there should ideally be only one)
    wp = work_packages[0]
    actual_project = wp.get('project_identifier')
    actual_subject = wp.get('subject')

    # CRITERION 2: Target Project Correct (60 pts)
    if actual_project == target_project:
        score += 60
        feedback_parts.append(f"PASS: Work package is in correct project '{target_project}'")
    else:
        feedback_parts.append(f"FAIL: Work package is in '{actual_project}', expected '{target_project}'")

    # CRITERION 3: Not in Source Project (10 pts)
    # If it's in target, it's definitionally not in source, but we check explicitly for clarity
    if actual_project != source_project:
        score += 10
    else:
        feedback_parts.append(f"FAIL: Work package is still in source project '{source_project}'")

    # CRITERION 4: Subject Unchanged (15 pts)
    if actual_subject == expected_subject:
        score += 15
        feedback_parts.append("PASS: Subject is unchanged")
    else:
        feedback_parts.append(f"FAIL: Subject changed to '{actual_subject}'")

    # CRITERION 5: Single Instance / No Duplicates (15 pts)
    # Differentiates 'Move' from 'Copy'
    if final_count == 1:
        score += 15
        feedback_parts.append("PASS: Exactly one instance found (Move successful)")
    elif final_count > 1:
        feedback_parts.append(f"FAIL: Found {final_count} instances. It appears the work package was Copied instead of Moved.")
    
    # ANTI-GAMING: Check for change
    initial_project = initial_state.get('project_identifier')
    if initial_project and initial_project == actual_project:
        feedback_parts.append("WARNING: Project identifier did not change from initial state.")
        if initial_project == source_project:
            score = 0
            feedback_parts.append("OVERRIDE: Score set to 0 because no change was detected.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }