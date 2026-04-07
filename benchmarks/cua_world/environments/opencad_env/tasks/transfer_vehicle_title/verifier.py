#!/usr/bin/env python3
"""Verifier for transfer_vehicle_title task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transfer_vehicle_title(traj, env_info, task_info):
    """
    Verify that the vehicle ownership was transferred correctly.
    
    Criteria:
    1. Vehicle 'XCAV8R' exists in database.
    2. Owner ID matches 'Sarah SiteLead'.
    3. Owner ID does NOT match 'John Driller'.
    4. Vehicle ID matches Initial Vehicle ID (record preserved/edited, not re-created).
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/transfer_vehicle_title_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    initial_veh_id = result.get('initial_vehicle_id', 0)
    john_id = result.get('john_id', 0)
    sarah_id = result.get('sarah_id', 0)
    
    db_state = result.get('db_state', {})
    vehicle_found = db_state.get('vehicle_found', False)
    current_veh_id = db_state.get('current_vehicle_id', 0)
    current_owner_id = db_state.get('current_owner_id', 0)

    score = 0
    feedback_parts = []

    # Check 1: Vehicle Exists (20 pts)
    if vehicle_found:
        score += 20
        feedback_parts.append("Vehicle XCAV8R found")
    else:
        feedback_parts.append("Vehicle XCAV8R NOT found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Owner Updated Correctly (50 pts)
    if current_owner_id == sarah_id and sarah_id != 0:
        score += 50
        feedback_parts.append("Owner updated to Sarah SiteLead")
    else:
        feedback_parts.append(f"Owner mismatch (Expected ID {sarah_id}, Got {current_owner_id})")

    # Check 3: Old Owner Removed (10 pts)
    # This is implicitly checked by Check 2 if we strictly require match, 
    # but specifically giving points for "Change happened" is good practice.
    if current_owner_id != john_id:
        score += 10
        feedback_parts.append("Old owner removed")
    else:
        feedback_parts.append("Owner is still John Driller")

    # Check 4: Record Preserved (20 pts)
    # The task asked to "edit" the record, not delete and recreate.
    if current_veh_id == initial_veh_id and initial_veh_id != 0:
        score += 20
        feedback_parts.append("Vehicle record preserved (ID match)")
    else:
        feedback_parts.append(f"Vehicle record ID changed (Initial {initial_veh_id} -> Current {current_veh_id}). Re-created?")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }