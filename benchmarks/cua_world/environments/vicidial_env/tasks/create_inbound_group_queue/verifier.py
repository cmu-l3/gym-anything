#!/usr/bin/env python3
"""
Verifier for create_inbound_group_queue task.

Checks if the inbound group 'RECALL01' exists in the Vicidial database
and verifies that all configuration parameters match the task specification.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_inbound_group(traj, env_info, task_info):
    """
    Verify the Inbound Group creation details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {})
    scoring = metadata.get('scoring', {})
    
    # Defaults if metadata missing
    if not expected_values:
        expected_values = {
            "group_name": "Product Recall Hotline",
            "group_color": "FF0000",
            "active": "Y",
            "queue_priority": "99",
            "next_agent_call": "longest_wait_agent",
            "fronter_display": "Y",
            "ingroup_recording_override": "ALLCALLS",
            "drop_call_seconds": "360",
            "after_hours_action": "MESSAGE"
        }
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Begin Scoring
    score = 0
    feedback_parts = []
    
    # Check 1: Group Existence (15 pts)
    if not result.get('group_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Inbound group 'RECALL01' was not found in the database."
        }
    
    score += scoring.get('exists', 15)
    feedback_parts.append("Group 'RECALL01' created.")
    
    # Check 2: Verify Individual Fields
    actual_data = result.get('group_data', {})
    
    # Map friendly names to db keys
    field_map = {
        "group_name": "Group Name",
        "group_color": "Group Color",
        "active": "Active Status",
        "queue_priority": "Queue Priority",
        "next_agent_call": "Routing Strategy",
        "fronter_display": "Fronter Display",
        "ingroup_recording_override": "Recording Override",
        "drop_call_seconds": "Drop Seconds",
        "after_hours_action": "After Hours Action"
    }

    for key, expected in expected_values.items():
        actual = str(actual_data.get(key, "")).strip()
        expected = str(expected).strip()
        points = scoring.get(key, 5) # Default 5 if not in scoring map
        
        # Case-insensitive comparison for text fields
        if actual.lower() == expected.lower():
            score += points
            # Don't clutter feedback with every correct field, just summarize later
        else:
            fname = field_map.get(key, key)
            feedback_parts.append(f"{fname} mismatch (Expected: '{expected}', Got: '{actual}')")

    # Final Evaluation
    max_score = 100
    pass_threshold = 60
    
    # Ensure feedback isn't empty if perfect
    if len(feedback_parts) == 1: # Only "Group created" is there
        feedback_parts.append("All configuration fields match perfectly!")
        
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": " | ".join(feedback_parts)
    }