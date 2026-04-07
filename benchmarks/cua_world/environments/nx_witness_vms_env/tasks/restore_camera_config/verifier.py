#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_camera_config(traj, env_info, task_info):
    """
    Verifies that the agent restored the camera configurations according to the backup file.
    
    Verification Logic:
    1. Reads the exported '/tmp/task_result.json' from the environment.
    2. Extracts the 'backup_configuration' (Goal) and 'final_system_state' (Actual).
    3. Matches cameras by 'physicalId'.
    4. Compares Name, Logical ID, and Recording Schedule.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    backup = result_data.get('backup_configuration', {})
    current_state = result_data.get('final_system_state', [])
    log_exists = result_data.get('log_exists', False)
    log_fresh = result_data.get('log_created_during_task', False)

    if not backup or not current_state:
        return {"passed": False, "score": 0, "feedback": "Task failed: Could not read system state or backup file missing."}

    # Scoring Config
    metadata = task_info.get('metadata', {}).get('scoring', {})
    pts_name = metadata.get('name_match_points', 10)
    pts_lid = metadata.get('logical_id_match_points', 7)
    pts_rec_enabled = metadata.get('recording_enabled_points', 7)
    pts_fps = metadata.get('fps_match_points', 5)
    pts_log = metadata.get('log_file_points', 8)
    
    score = 0
    feedback = []
    
    # Process Log File
    if log_exists and log_fresh:
        score += pts_log
        feedback.append("Log file created successfully.")
    elif log_exists:
        score += pts_log // 2
        feedback.append("Log file exists but timestamp suggests it wasn't created during this session.")
    else:
        feedback.append("Log file missing.")

    # Create a lookup for current state by physicalId
    # physicalId is the immutable hardware ID, 'id' is the internal GUID
    current_map = {cam.get('physicalId'): cam for cam in current_state}
    
    cameras_checked = 0
    changes_detected = False

    target_cameras = backup.get('cameras', [])
    if not target_cameras:
        return {"passed": False, "score": 0, "feedback": "Error: Backup file in environment was empty."}

    for target in target_cameras:
        phys_id = target.get('physicalId')
        
        if phys_id not in current_map:
            feedback.append(f"Camera {phys_id} not found in system!")
            continue

        cameras_checked += 1
        actual = current_map[phys_id]
        
        # Verify Name
        target_name = target.get('name')
        actual_name = actual.get('name')
        if actual_name == target_name:
            score += pts_name
            changes_detected = True # If it matches target, it must have changed from corrupt state
        else:
            feedback.append(f"Cam '{target_name}': Name mismatch (Found: '{actual_name}')")

        # Verify Logical ID
        # JSON might have int, API might return string or int
        target_lid = str(target.get('logicalId', ''))
        actual_lid = str(actual.get('logicalId', ''))
        if actual_lid == target_lid:
            score += pts_lid
            if actual_lid != "0": changes_detected = True
        else:
            feedback.append(f"Cam '{target_name}': Logical ID mismatch (Expected: {target_lid}, Found: {actual_lid})")

        # Verify Recording Schedule
        # Target: {'enabled': true, 'fps': 15, ...}
        # Actual: 'schedule': {'isEnabled': true, 'tasks': [...]}
        target_rec = target.get('recording', {})
        actual_sched = actual.get('schedule', {})
        
        # Check Enabled
        if target_rec.get('enabled') == actual_sched.get('isEnabled'):
            score += pts_rec_enabled
            if actual_sched.get('isEnabled') is True: changes_detected = True
        else:
            feedback.append(f"Cam '{target_name}': Recording enabled mismatch")

        # Check FPS
        # We check the tasks list in the schedule. If ANY task has the matching FPS, we give credit.
        target_fps = target_rec.get('fps')
        actual_tasks = actual_sched.get('tasks', [])
        
        fps_match = False
        if not actual_tasks and target_fps == 0:
            fps_match = True
        else:
            for task in actual_tasks:
                if int(task.get('fps', 0)) == int(target_fps):
                    fps_match = True
                    break
        
        if fps_match:
            score += pts_fps
        else:
            feedback.append(f"Cam '{target_name}': FPS settings mismatch")

    # Change detection bonus
    if changes_detected:
        score += metadata.get('change_detected_points', 5)

    # Normalize score if needed, but the points should sum to ~100 based on 3 cameras
    # 3 cams * (10+7+7+5) = 3 * 29 = 87
    # Log = 8
    # Change bonus = 5
    # Total = 100
    
    score = min(100, score)
    
    passed = score >= 60
    
    final_feedback = f"Score: {score}/100. " + "; ".join(feedback)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }