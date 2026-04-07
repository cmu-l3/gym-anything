#!/usr/bin/env python3
"""
Verifier for mobile_broadcast_kit_assembly task.

Verifies:
1. Cameras are checked out to the correct users.
2. Peripheral components are checked out to the correct parent cameras.
3. The broken microphone (MIC-003) was ignored.
4. Correct checkout notes are applied to the cameras.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mobile_broadcast_kit_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback = []

    users = result.get('users', {})
    cameras = result.get('cameras', {})
    components = result.get('components', {})
    statuses = result.get('statuses', {})

    # Extracted IDs
    usr_elena = str(users.get('elena', '0'))
    usr_marcus = str(users.get('marcus', '0'))
    usr_sarah = str(users.get('sarah', '0'))
    repair_id = str(statuses.get('repair_id', '0'))

    # Helper function to check parent checkout
    def check_camera_checkout(cam_key, expected_user_id, user_name, criteria_pts):
        nonlocal score
        cam_data = cameras.get(cam_key, {})
        state = cam_data.get('state', {})
        assigned_to = str(state.get('assigned_to', ''))
        assigned_type = str(state.get('assigned_type', '')).lower()
        
        if assigned_to == expected_user_id and 'user' in assigned_type:
            score += criteria_pts
            feedback.append(f"Pass: {cam_key} correctly checked out to {user_name} (+{criteria_pts})")
            return True
        else:
            feedback.append(f"Fail: {cam_key} not correctly checked out to {user_name}")
            return False

    # Helper function to check kit assembly
    def check_kit_assembly(cam_key, expected_comps, kit_name, criteria_pts):
        nonlocal score
        cam_id = str(cameras.get(cam_key, {}).get('id', '0'))
        if cam_id == '0':
            feedback.append(f"Fail: Could not resolve ID for {cam_key}")
            return False

        all_correct = True
        for comp_key in expected_comps:
            comp_state = components.get(comp_key, {})
            assigned_to = str(comp_state.get('assigned_to', ''))
            assigned_type = str(comp_state.get('assigned_type', '')).lower()
            
            if assigned_to != cam_id or 'asset' not in assigned_type:
                all_correct = False
                feedback.append(f"Fail: {comp_key} not checked out to {cam_key}")

        if all_correct:
            score += criteria_pts
            feedback.append(f"Pass: {kit_name} correctly assembled onto {cam_key} (+{criteria_pts})")
            return True
        return False

    # --- C1, C2, C3: Camera Checkouts ---
    c1_pass = check_camera_checkout('cam1', usr_elena, 'Elena Rostova', 10)
    c2_pass = check_camera_checkout('cam2', usr_marcus, 'Marcus Johnson', 10)
    c3_pass = check_camera_checkout('cam3', usr_sarah, 'Sarah Chen', 10)

    # --- Do Nothing Check ---
    # We check if any of the main cameras moved or if any kits were assigned
    any_camera_checked_out = c1_pass or c2_pass or c3_pass
    any_component_moved = False
    for comp in components.values():
        if comp.get('assigned_to') is not None and str(comp.get('assigned_to')) != 'null':
            any_component_moved = True
            break
            
    if not any_camera_checked_out and not any_component_moved:
         return {
            "passed": False,
            "score": 0,
            "feedback": "DO-NOTHING: No assets or components were checked out or moved."
        }

    # --- C4, C5, C6: Kit Assemblies ---
    check_kit_assembly('cam1', ['lens1', 'mic1', 'bat1'], 'Kit 1', 15)
    check_kit_assembly('cam2', ['lens2', 'mic2', 'bat2'], 'Kit 2', 15)
    check_kit_assembly('cam3', ['lens3', 'mic4', 'bat3'], 'Kit 3', 15)

    # --- C7: Damaged Asset Ignored ---
    mic3_state = components.get('mic3', {})
    mic3_assigned = str(mic3_state.get('assigned_to', 'null'))
    mic3_status = str(mic3_state.get('status_id', ''))
    
    if (mic3_assigned == 'null' or mic3_assigned == '' or mic3_assigned == 'None') and mic3_status == repair_id:
        score += 10
        feedback.append("Pass: Damaged MIC-003 was properly ignored and left Out for Repair (+10)")
    else:
        feedback.append("Fail: Damaged MIC-003 was incorrectly checked out or modified")

    # --- C8: Checkout Notes ---
    notes_correct = 0
    for cam_key in ['cam1', 'cam2', 'cam3']:
        note = str(cameras.get(cam_key, {}).get('note', '')).lower()
        if 'q3 field work' in note:
            notes_correct += 1
            
    if notes_correct == 3:
        score += 15
        feedback.append("Pass: All cameras have correct checkout notes (+15)")
    elif notes_correct > 0:
        partial = int(15 * (notes_correct / 3.0))
        score += partial
        feedback.append(f"Partial: {notes_correct}/3 cameras have correct checkout notes (+{partial})")
    else:
        feedback.append("Fail: No cameras have the required checkout notes")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }