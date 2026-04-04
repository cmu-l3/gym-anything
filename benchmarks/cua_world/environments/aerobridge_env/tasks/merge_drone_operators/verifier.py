#!/usr/bin/env python3
"""
Verifier for merge_drone_operators task.

Verification Criteria:
1. Source Company ('Valley UAV Logistics') must be deleted. (20 pts)
2. Target Company ('Summit Drone Services') must have all aircraft (Original + Transferred). (30 pts)
3. Target Company must have all people (Original + Transferred). (30 pts)
4. No assets should be lost (Total counts must match baseline). (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_drone_operators(traj, env_info, task_info):
    """
    Verify that the agent correctly merged the two operators.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    
    # Expected final state calculation:
    # Target Final = Target Initial (2) + Source Initial (3) = 5
    EXPECTED_TARGET_AIRCRAFT = metadata.get('target_aircraft_baseline', 2) + metadata.get('source_aircraft_count', 3)
    
    # Target Final = Target Initial (1) + Source Initial (2) = 3
    EXPECTED_TARGET_PERSON = metadata.get('target_person_baseline', 1) + metadata.get('source_person_count', 2)
    
    # Total System Counts (should not change)
    EXPECTED_TOTAL_AIRCRAFT = metadata.get('total_aircraft_count', 5)
    EXPECTED_TOTAL_PERSON = metadata.get('total_person_count', 3)

    # Load result from container
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
    feedback_parts = []
    
    # 1. Check Source Deletion (20 pts)
    if not result.get('source_exists', True):
        score += 20
        feedback_parts.append("✓ Source company 'Valley UAV Logistics' successfully dissolved.")
    else:
        feedback_parts.append("✗ Source company 'Valley UAV Logistics' still exists.")

    # 2. Check Aircraft Transfer (30 pts)
    actual_target_ac = result.get('target_aircraft_count', 0)
    if actual_target_ac == EXPECTED_TARGET_AIRCRAFT:
        score += 30
        feedback_parts.append(f"✓ All aircraft transferred successfully (Count: {actual_target_ac}).")
    else:
        feedback_parts.append(f"✗ Aircraft count mismatch for Summit Drone Services. Expected {EXPECTED_TARGET_AIRCRAFT}, got {actual_target_ac}. (Did you transfer all drones?)")

    # 3. Check Person Transfer (30 pts)
    actual_target_person = result.get('target_person_count', 0)
    if actual_target_person == EXPECTED_TARGET_PERSON:
        score += 30
        feedback_parts.append(f"✓ All personnel transferred successfully (Count: {actual_target_person}).")
    else:
        feedback_parts.append(f"✗ Personnel count mismatch for Summit Drone Services. Expected {EXPECTED_TARGET_PERSON}, got {actual_target_person}. (Did you transfer all staff?)")

    # 4. Check Data Integrity (20 pts)
    # This detects if the agent simply deleted the assets instead of moving them, or deleted the company while it still had assets
    total_ac = result.get('total_aircraft_count', 0)
    total_person = result.get('total_person_count', 0)
    
    data_loss = False
    if total_ac < EXPECTED_TOTAL_AIRCRAFT:
        feedback_parts.append(f"✗ DATA LOSS: {EXPECTED_TOTAL_AIRCRAFT - total_ac} aircraft were deleted from the system!")
        data_loss = True
    if total_person < EXPECTED_TOTAL_PERSON:
        feedback_parts.append(f"✗ DATA LOSS: {EXPECTED_TOTAL_PERSON - total_person} person records were deleted from the system!")
        data_loss = True
        
    if not data_loss:
        score += 20
        feedback_parts.append("✓ Data integrity maintained (no assets lost).")

    passed = (score >= 80) # Requires successful transfer AND deletion of old entity
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }