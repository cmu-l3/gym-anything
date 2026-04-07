#!/usr/bin/env python3
"""
Verifier for create_custom_tracker task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_tracker(traj, env_info, task_info):
    """
    Verifies:
    1. A tracker named "Permit Application" exists.
    2. An issue exists with subject containing "Wind Farm Alpha".
    3. The issue uses the "Permit Application" tracker.
    4. The issue was created during the task window.
    5. Issue priority and description details match expectations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tracker = metadata.get('expected_tracker_name', 'Permit Application')
    required_desc_fragment = metadata.get('required_description_fragment', 'regional planning authority')
    
    score = 0
    feedback_parts = []
    
    # Load result
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
            
    # Check 1: Tracker Creation (30 points)
    tracker_found = result.get('tracker_found', False)
    tracker_info = result.get('tracker_info', {})
    
    if tracker_found and tracker_info.get('name') == expected_tracker:
        score += 30
        feedback_parts.append(f"Tracker '{expected_tracker}' created successfully.")
        
        # Bonus: Check default status if available in API (often limited in basic view)
        # We'll skip strict status check via API as it might need detailed endpoint
    else:
        feedback_parts.append(f"Tracker '{expected_tracker}' NOT found.")
        
    # Check 2: Issue Creation (20 points)
    issue_found = result.get('issue_found', False)
    issue_info = result.get('issue_info', {})
    
    if issue_found:
        score += 20
        feedback_parts.append("Target issue created.")
        
        # Check 3: Issue uses correct tracker (20 points)
        # API returns tracker as object: {"id": 1, "name": "Bug"}
        issue_tracker_name = issue_info.get('tracker', {}).get('name', '')
        if issue_tracker_name == expected_tracker:
            score += 20
            feedback_parts.append(f"Issue correctly assigned to '{expected_tracker}'.")
        else:
            feedback_parts.append(f"Issue assigned to wrong tracker: '{issue_tracker_name}'.")

        # Check 4: Issue Details (15 points)
        issue_desc = issue_info.get('description', '')
        issue_priority = issue_info.get('priority', {}).get('name', '')
        
        details_score = 0
        if required_desc_fragment.lower() in issue_desc.lower():
            details_score += 10
        if issue_priority == 'Normal':
            details_score += 5
            
        score += details_score
        if details_score == 15:
            feedback_parts.append("Issue details (description/priority) are correct.")
        else:
            feedback_parts.append("Issue details partially incorrect.")

        # Check 5: Anti-gaming Timestamp (15 points)
        if result.get('issue_created_during_task', False):
            score += 15
            feedback_parts.append("Issue created during task window.")
        else:
            feedback_parts.append("Issue timestamp invalid or pre-existing.")
            
    else:
        feedback_parts.append("Target issue NOT found.")

    passed = score >= 60 and tracker_found and issue_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }