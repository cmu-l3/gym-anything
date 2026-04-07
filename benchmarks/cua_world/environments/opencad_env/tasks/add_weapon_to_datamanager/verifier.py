#!/usr/bin/env python3
"""Verifier for add_weapon_to_datamanager task."""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_weapon_to_datamanager(traj, env_info, task_info):
    """
    Verify that the agent added the specific weapon to the Data Manager.
    
    Criteria:
    1. Database record exists for "Remington 870 Breacher" (35 pts)
    2. Weapon type is "Shotgun" (15 pts)
    3. Record count increased (anti-gaming) (15 pts)
    4. VLM verification of UI workflow (35 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Remington 870 Breacher').lower()
    expected_type = metadata.get('expected_type', 'Shotgun').lower()

    # 1. Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_weapon_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Programmatic Checks ---
    
    # Check 1: Record Exists (35 pts)
    weapon_found = result.get('weapon_found', False)
    weapon_data = result.get('weapon', {})
    actual_name = (weapon_data.get('name') or '').lower()
    
    if weapon_found:
        if expected_name in actual_name or actual_name in expected_name:
            score += 35
            feedback_parts.append("Weapon record found with correct name")
        else:
            score += 10 # Partial credit for creating *something* new
            feedback_parts.append(f"New weapon found but name mismatch: expected '{expected_name}', got '{actual_name}'")
    else:
        feedback_parts.append("No new weapon record found in database")

    # Check 2: Correct Type (15 pts)
    actual_type = (weapon_data.get('type') or '').lower()
    if weapon_found and (expected_type == actual_type or expected_type in actual_type):
        score += 15
        feedback_parts.append(f"Weapon type matches: {actual_type}")
    elif weapon_found:
        feedback_parts.append(f"Weapon type mismatch: expected '{expected_type}', got '{actual_type}'")

    # Check 3: Count Increased (15 pts)
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    if current_count > initial_count:
        score += 15
        feedback_parts.append("Database record count increased")
    else:
        feedback_parts.append("No increase in database record count")

    # --- VLM Verification (35 pts) ---
    # We check if the agent actually used the Admin/Data Manager UI
    
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        # We look for "Data Manager", "Weapons", and the form inputs
        prompt = """
        Review this sequence of screenshots from an OpenCAD administration task.
        The user should:
        1. Access the 'Admin' panel
        2. Enter the 'Data Manager'
        3. Select 'Weapons'
        4. Fill in a form with 'Remington 870 Breacher' and 'Shotgun'
        
        Do you see evidence of:
        A) The Data Manager interface?
        B) The Weapons list or input form?
        C) The specific text 'Remington' or 'Shotgun' being entered?
        
        Respond with JSON: {"data_manager_visible": bool, "weapons_form_visible": bool, "correct_text_entered": bool}
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_shot], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('data_manager_visible'): vlm_score += 10
            if parsed.get('weapons_form_visible'): vlm_score += 10
            if parsed.get('correct_text_entered'): vlm_score += 15
            
            score += vlm_score
            feedback_parts.append(f"VLM verification score: {vlm_score}/35")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback: if programmatic passed, give partial VLM points
            if weapon_found:
                score += 20
                feedback_parts.append("VLM failed but database verified action")
    else:
        feedback_parts.append("VLM not available")
        if weapon_found:
             score += 35 # Grant points if programmatic check passed to avoid penalizing for missing VLM

    # Final Pass/Fail
    passed = score >= 65 and weapon_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": ". ".join(feedback_parts)
    }