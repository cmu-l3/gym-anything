#!/usr/bin/env python3
"""
Verifier for camera_replacement_provisioning task.

Verifies:
1. Old camera is renamed (contains "Decommissioned") and disabled.
2. New camera is renamed ("Server Room Camera") and enabled.
3. New camera has the correct recording schedule (migrated from old).
4. Maintenance report exists and is valid JSON.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_camera_replacement(traj, env_info, task_info):
    """
    Verify the camera replacement workflow using data exported from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_OLD_RENAMED = 15
    SCORE_OLD_DISABLED = 15
    SCORE_NEW_RENAMED = 15
    SCORE_NEW_ENABLED = 10
    SCORE_SCHEDULE_MIGRATED = 35
    SCORE_REPORT = 10
    
    TOTAL_SCORE = 0
    feedback_parts = []
    
    # Define expected values from metadata/task description
    EXPECTED_NEW_NAME = "Server Room Camera"
    EXPECTED_FPS = 7
    EXPECTED_QUALITY = "low"

    # Load result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse states
    faulty_state = result.get('faulty_camera_state', {})
    new_state = result.get('new_camera_state', {})
    
    if not faulty_state or not new_state:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve camera states from VMS API"}

    # 1. Verify Old Camera State
    old_name = faulty_state.get('name', '')
    old_enabled = faulty_state.get('enabled', True) # Default to true if missing

    if "Decommissioned" in old_name:
        TOTAL_SCORE += SCORE_OLD_RENAMED
        feedback_parts.append("✅ Old camera renamed correctly")
    else:
        feedback_parts.append(f"❌ Old camera name incorrect ('{old_name}')")

    if not old_enabled: # Should be False
        TOTAL_SCORE += SCORE_OLD_DISABLED
        feedback_parts.append("✅ Old camera disabled")
    else:
        feedback_parts.append("❌ Old camera still enabled")

    # 2. Verify New Camera State
    new_name = new_state.get('name', '')
    new_enabled = new_state.get('enabled', False)

    if new_name == EXPECTED_NEW_NAME:
        TOTAL_SCORE += SCORE_NEW_RENAMED
        feedback_parts.append("✅ New camera named correctly")
    else:
        feedback_parts.append(f"❌ New camera name incorrect ('{new_name}')")

    if new_enabled:
        TOTAL_SCORE += SCORE_NEW_ENABLED
        feedback_parts.append("✅ New camera enabled")
    else:
        feedback_parts.append("❌ New camera disabled")

    # 3. Verify Schedule Migration (The hardest part)
    # We look for a task in the schedule that matches expected params
    schedule = new_state.get('schedule', {})
    tasks = schedule.get('tasks', [])
    
    schedule_correct = False
    if schedule.get('isEnabled'):
        for task in tasks:
            # Check for the unique signature we set in setup
            if task.get('fps') == EXPECTED_FPS and task.get('streamQuality') == EXPECTED_QUALITY:
                schedule_correct = True
                break
    
    if schedule_correct:
        TOTAL_SCORE += SCORE_SCHEDULE_MIGRATED
        feedback_parts.append("✅ Recording schedule migrated successfully")
    else:
        feedback_parts.append(f"❌ Recording schedule not migrated (Expected FPS {EXPECTED_FPS}, Quality {EXPECTED_QUALITY})")

    # 4. Verify Report
    if result.get('report_exists') and result.get('report_valid'):
        TOTAL_SCORE += SCORE_REPORT
        feedback_parts.append("✅ Maintenance report created")
    else:
        feedback_parts.append("❌ Maintenance report missing or invalid")

    # Determine pass/fail
    # Must at least migrate schedule and rename/enable new camera to pass
    PASS_THRESHOLD = 75
    passed = TOTAL_SCORE >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": TOTAL_SCORE,
        "feedback": " | ".join(feedback_parts)
    }