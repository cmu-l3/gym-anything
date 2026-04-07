#!/usr/bin/env python3
"""
Verifier for assign_camera_logical_ids task.

Verifies that the correct logical IDs were assigned to specific cameras
by inspecting the API response captured in the result JSON.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_camera_logical_ids(traj, env_info, task_info):
    """
    Verify camera logical ID assignments.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected assignments from metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('target_assignments', {
        "Parking Lot Camera": 101,
        "Entrance Camera": 102,
        "Server Room Camera": 103
    })
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for basic errors
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Error during export: {result['error']}"}

    devices = result.get('devices', [])
    if not devices:
        return {"passed": False, "score": 0, "feedback": "No devices found in system state."}

    # Map current state by name (lowercase for robust matching)
    current_state = {}
    for d in devices:
        name = d.get('name', '').strip()
        logical_id = d.get('logicalId', 0)
        # Convert explicit "0" string or null to integer 0
        try:
            logical_id = int(logical_id)
        except (ValueError, TypeError):
            logical_id = 0
            
        if name:
            current_state[name.lower()] = logical_id

    # Score calculation
    score = 0
    feedback_lines = []
    correct_count = 0
    total_targets = len(targets)
    
    # Points per camera (90 total for individual cams, 10 bonus)
    points_per_cam = 30

    for cam_name, expected_id in targets.items():
        actual_id = current_state.get(cam_name.lower(), None)
        
        if actual_id is None:
            feedback_lines.append(f"❌ '{cam_name}': Camera not found in system.")
        elif actual_id == expected_id:
            score += points_per_cam
            correct_count += 1
            feedback_lines.append(f"✅ '{cam_name}': Assigned ID {actual_id} (Correct).")
        else:
            feedback_lines.append(f"❌ '{cam_name}': Found ID {actual_id}, expected {expected_id}.")

    # Bonus points for 100% completion
    if correct_count == total_targets:
        score += 10
        feedback_lines.append("✅ Bonus: All assignments correct (+10).")

    # Anti-gaming check: Task start time must verify setup ran
    task_start = result.get('task_start', 0)
    if task_start == 0:
        feedback_lines.append("⚠️ Warning: Setup script timestamp missing.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }