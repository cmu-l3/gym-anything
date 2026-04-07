#!/usr/bin/env python3
"""
Verifier stub for implement_zone_recording_policy.

Primary verification is done via vlm_checklist_verifier.
This stub loads the exported task result and performs basic structural checks.
"""
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_zone_recording_policy(traj, env_info, task_info):
    """
    Stub verifier: loads task result, returns basic pass/fail.
    Full verification is handled by VLM checklist evaluator.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_devices = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)

        # Load the API device dump
        api_dump_path = result_data.get("api_devices_dump_path")
        if not api_dump_path:
            return {"passed": False, "score": 0, "feedback": "No API data captured."}

        copy_from_env(api_dump_path, temp_devices.name)
        with open(temp_devices.name, 'r') as f:
            devices = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading task data: {str(e)}"}
    finally:
        for p in [temp_result.name, temp_devices.name]:
            if os.path.exists(p):
                os.unlink(p)

    # --- Stub scoring: basic checks ---
    score = 0
    feedback_lines = []

    # Build camera map
    camera_map = {d.get('name'): d for d in devices if d.get('name')}

    # Check that at least some cameras have schedules enabled
    cameras_with_schedules = 0
    for cam_name in ["Parking Lot Camera", "Entrance Camera", "Server Room Camera"]:
        cam = camera_map.get(cam_name)
        if not cam:
            continue
        sched = cam.get('schedule', {})
        if sched.get('isEnabled') and len(sched.get('tasks', [])) > 0:
            cameras_with_schedules += 1

    score += cameras_with_schedules * 25  # up to 75
    feedback_lines.append(f"{cameras_with_schedules}/3 cameras have schedules enabled")

    # Check report file
    if result_data.get('report_exists') and result_data.get('report_created_during_task'):
        score += 10
        feedback_lines.append("Report file created during task.")
    else:
        feedback_lines.append("Report file missing or not created during task.")

    return {
        "passed": score >= 50,
        "score": min(score, 100),
        "feedback": "\n".join(feedback_lines)
    }
