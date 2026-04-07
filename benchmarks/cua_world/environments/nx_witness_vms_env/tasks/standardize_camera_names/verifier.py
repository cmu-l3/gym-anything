#!/usr/bin/env python3
"""
Verifier for standardize_camera_names task.

Verifies that:
1. Specific cameras have been renamed correctly according to the mapping.
2. Old informal names no longer exist.
3. The total number of cameras has not changed (prevents deleting cameras to "solve" the name check).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_standardize_camera_names(traj, env_info, task_info):
    """
    Verify camera renaming task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract data
    final_state = result.get('final_camera_state', {})
    current_names = set(final_state.get('names', []))
    current_count = final_state.get('count', 0)
    initial_count = int(result.get('initial_camera_count', 0))

    # Define expectations
    # Mapping: Old Name -> New Name
    metadata = task_info.get('metadata', {})
    expected_mapping = metadata.get('expected_mapping', {
        "Parking Lot Camera": "HQ-EXT-PKG-01",
        "Entrance Camera": "HQ-1F-ENT-01",
        "Server Room Camera": "HQ-B1-SVR-01",
        "Lobby Camera": "HQ-1F-LBY-01",
        "Loading Dock Camera": "HQ-EXT-LDK-01"
    })

    score = 0
    max_score = 100
    feedback_parts = []

    # CRITERION 1: Count Preservation (Anti-gaming) (10 pts)
    # If cameras were deleted, the agent might have failed to rename but removed the "evidence"
    if current_count >= initial_count and initial_count > 0:
        score += 10
        feedback_parts.append(f"Camera inventory preserved ({current_count} cameras)")
    else:
        feedback_parts.append(f"Camera count changed (Initial: {initial_count}, Final: {current_count})")
        # Critical failure if count dropped significantly, but we continue scoring

    # CRITERION 2: Required Renames (25 pts per core camera)
    # We check if the NEW name exists in the set of current names
    # Note: We can't easily track ID-to-Name without complex history, 
    # so we assume if "HQ-EXT-PKG-01" exists, it was done correctly.
    
    core_cameras = [
        ("HQ-EXT-PKG-01", 25),
        ("HQ-1F-ENT-01", 25),
        ("HQ-B1-SVR-01", 25)
    ]
    
    for name, points in core_cameras:
        if name in current_names:
            score += points
            feedback_parts.append(f"Found required camera: {name}")
        else:
            feedback_parts.append(f"Missing required camera: {name}")

    # CRITERION 3: No Old Names Remaining (15 pts)
    old_names_found = []
    for old_name in expected_mapping.keys():
        if old_name in current_names:
            old_names_found.append(old_name)
    
    if not old_names_found:
        score += 15
        feedback_parts.append("All old informal names removed")
    else:
        feedback_parts.append(f"Old names still present: {', '.join(old_names_found)}")

    # Bonus points for extra cameras (if they existed in the environment)
    # The setup script tries to create 5 cameras, but sometimes only 3 might initialize.
    # We normalized score to 100 based on the 3 core ones + clean state.
    # If the environment has more, we grant points but cap at 100.
    
    extra_cameras = ["HQ-1F-LBY-01", "HQ-EXT-LDK-01"]
    for name in extra_cameras:
        if name in current_names:
            score += 5
            feedback_parts.append(f"Bonus: Found {name}")

    # Cap score
    score = min(score, 100)

    # Pass/Fail determination
    # Must have at least the first 2 core cameras renamed AND reasonable score
    passed = score >= 60 and ("HQ-EXT-PKG-01" in current_names) and ("HQ-1F-ENT-01" in current_names)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }