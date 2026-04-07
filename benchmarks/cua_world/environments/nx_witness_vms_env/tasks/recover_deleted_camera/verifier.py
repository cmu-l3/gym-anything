#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recover_deleted_camera(traj, env_info, task_info):
    """
    Verify that the agent successfully restored the deleted camera.
    
    Criteria:
    1. Camera "Server Room Camera" exists in the system (40 pts)
    2. Camera status is "Online" (20 pts)
    3. Recording is enabled (20 pts)
    4. Inventory file was accessed (evidence of gathering info) (10 pts)
    5. FPS is set correctly (~15) (10 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # Criterion 1: Camera Re-added (40 pts)
    if result.get("camera_found", False):
        score += 40
        feedback.append("Camera 'Server Room Camera' found in system.")
    else:
        feedback.append("Camera 'Server Room Camera' NOT found.")
        return {"passed": False, "score": 0, "feedback": "Failed to add camera"}

    # Criterion 2: Status Online (20 pts)
    # Note: 'Online' status depends on testcamera simulation. If testcamera is running, it should be online.
    if result.get("camera_online", False):
        score += 20
        feedback.append("Camera status is Online.")
    else:
        feedback.append("Camera added but status is NOT Online (check IP/credentials).")

    # Criterion 3: Recording Enabled (20 pts)
    if result.get("recording_enabled", False):
        score += 20
        feedback.append("Recording schedule enabled.")
    else:
        feedback.append("Recording schedule NOT enabled.")

    # Criterion 4: Inventory File Accessed (10 pts)
    if result.get("inventory_file_accessed", False):
        score += 10
        feedback.append("Network inventory file accessed.")
    else:
        feedback.append("Did not detect access to inventory file (did you guess the IP?).")

    # Criterion 5: FPS Setting (10 pts)
    fps = result.get("recording_fps", 0)
    if 10 <= fps <= 20:
        score += 10
        feedback.append(f"Recording FPS set to {fps} (Acceptable range 10-20).")
    elif result.get("recording_enabled", False):
        feedback.append(f"Recording enabled but FPS {fps} is outside target range (15).")
        score += 5 # Partial credit

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }