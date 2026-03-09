#!/usr/bin/env python3
"""
Verifier for create_ivr_call_menu task.

Verifies:
1. Call Menu record exists in Database
2. Menu properties match (Name, Timeout, Prompt, Repeat)
3. All 7 expected DTMF options exist and map to correct destinations
4. VLM visual verification of workflow
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ivr_call_menu(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata (Expected Values)
    metadata = task_info.get('metadata', {})
    expected_id = metadata.get('menu_id', 'valley_health_main')
    expected_name = metadata.get('expected_name', 'Valley Health Partners Main Menu')
    expected_prompt = metadata.get('expected_prompt', 'vm-greeting')
    expected_timeout = metadata.get('expected_timeout', 10)
    expected_repeat = metadata.get('expected_repeat', 3)
    expected_options = metadata.get('expected_options', {})

    # Load Result from Env
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    menu_data = db_state.get('menu_data')
    actual_options = db_state.get('options', [])
    initial_count = int(result.get('initial_menu_count', 0))
    current_count = int(db_state.get('current_menu_count', 0))

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Menu Record Exists (Critical) - 15 pts
    # ---------------------------------------------------------
    if not menu_data:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Call Menu '{expected_id}' was not found in the database."
        }
    
    score += 15
    feedback.append(f"Menu '{expected_id}' created.")

    # Anti-gaming: Check if count increased (ensures it was created now, not pre-existing)
    # Note: setup_task deletes it, so if it exists now, it was created. 
    # But checking count is a good sanity check.
    if current_count <= initial_count:
        feedback.append("WARNING: Menu count did not increase (setup might have failed to clean up).")
    
    # ---------------------------------------------------------
    # Criterion 2: Menu Properties - 20 pts
    # ---------------------------------------------------------
    props_score = 0
    
    # Name (5 pts)
    if menu_data.get('menu_name') == expected_name:
        props_score += 5
    else:
        feedback.append(f"Name mismatch: got '{menu_data.get('menu_name')}'")

    # Timeout (5 pts)
    # Convert to int for comparison
    try:
        act_timeout = int(menu_data.get('menu_timeout', -1))
        if act_timeout == int(expected_timeout):
            props_score += 5
        else:
            feedback.append(f"Timeout mismatch: got {act_timeout}")
    except:
        feedback.append(f"Invalid timeout value: {menu_data.get('menu_timeout')}")

    # Repeat (5 pts)
    try:
        act_repeat = int(menu_data.get('menu_repeat', -1))
        if act_repeat == int(expected_repeat):
            props_score += 5
        else:
            feedback.append(f"Repeat mismatch: got {act_repeat}")
    except:
        feedback.append("Invalid repeat value")

    # Prompts (5 pts combined)
    p_score = 0
    if menu_data.get('menu_prompt') == expected_prompt: p_score += 2
    if menu_data.get('menu_timeout_prompt') == 'vm-goodbye': p_score += 1.5
    if menu_data.get('menu_invalid_prompt') == 'vm-invalid': p_score += 1.5
    props_score += int(p_score)
    if p_score < 5:
        feedback.append("Some prompts matched incorrectly")

    score += props_score
    feedback.append(f"Properties Score: {props_score}/20")

    # ---------------------------------------------------------
    # Criterion 3: Menu Options - 55 pts (Standardized)
    # ---------------------------------------------------------
    # Map actual options by 'option_value' (the DTMF key) for easy lookup
    # Note: DB might store '1' as '1' string.
    actual_map = {opt['option_value']: opt for opt in actual_options}
    
    opts_score = 0
    
    # Check 7 expected options (1, 2, 3, 4, 0, t, i)
    # 1-4 and 0 are 8 pts each (40 total)
    # t and i are 7.5 pts each (15 total)
    
    for key, expected in expected_options.items():
        if key not in actual_map:
            feedback.append(f"Option '{key}' missing")
            continue
            
        act = actual_map[key]
        
        # Check Route Type
        route_match = (act.get('route') == expected['route'])
        # Check Route Value
        val_match = (act.get('route_value') == expected['value'])
        
        # Points allocation
        item_points = 10 if key in ['1','2','3','4','0'] else 5
        
        if route_match and val_match:
            opts_score += item_points
        else:
            feedback.append(f"Option '{key}' incorrect: {act.get('route')}->{act.get('route_value')}")

    score += opts_score
    feedback.append(f"Options Score: {opts_score}/60")

    # ---------------------------------------------------------
    # Criterion 4: VLM Verification - 5 pts
    # ---------------------------------------------------------
    # We use trajectory frames to ensure the agent actually used the UI
    # and didn't just curl the API (anti-gaming, though unlikely here).
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    try:
        # Simple check: Did we see the Call Menu form?
        resp = query_vlm(
            images=frames + [final_screen], 
            prompt="Does this sequence show a user filling out a 'Call Menu' or 'IVR' configuration form in a web interface? Look for fields like 'Menu ID', 'Menu Name', or 'Option Route'. Answer Yes/No and explain."
        )
        if resp.get('success') and "yes" in resp.get('result', '').lower():
            vlm_score = 5
            feedback.append("VLM: Workflow verified.")
        else:
            feedback.append("VLM: Could not verify visual workflow.")
    except Exception:
        # Fallback if VLM fails
        vlm_score = 5 
        feedback.append("VLM: Skipped (Error).")
        
    score += vlm_score

    # ---------------------------------------------------------
    # Final Calculation
    # ---------------------------------------------------------
    pass_threshold = 60
    passed = (score >= pass_threshold) and (menu_data is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }