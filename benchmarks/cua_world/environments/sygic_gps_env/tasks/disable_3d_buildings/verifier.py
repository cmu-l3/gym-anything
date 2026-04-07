#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_disable_3d_buildings(traj, env_info, task_info):
    """
    Verifies that the agent disabled 3D buildings in Sygic GPS Navigation.
    
    Strategy:
    1. VLM Trajectory Analysis (Primary):
       - Did the agent navigate to Settings?
       - Did the agent find a "Buildings" or "Landmarks" toggle?
       - Did the agent switch it OFF?
    2. Final State Check:
       - Is the app running?
       - Does the map look flatter/cleaner? (Secondary VLM check)
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment connection failed (copy_from_env missing)."}

    # Temp file management
    temp_dir = tempfile.mkdtemp()
    local_result_json = os.path.join(temp_dir, "task_result.json")
    local_prefs_dump = os.path.join(temp_dir, "prefs_dump.txt")
    
    try:
        # Copy result JSON
        copy_from_env("/data/local/tmp/disable_3d_buildings/task_result.json", local_result_json)
        with open(local_result_json, 'r') as f:
            result_data = json.load(f)
            
        # Optional: Copy prefs dump for debugging/secondary signal
        try:
            copy_from_env("/data/local/tmp/disable_3d_buildings/prefs_dump.txt", local_prefs_dump)
            with open(local_prefs_dump, 'r') as f:
                prefs_content = f.read()
        except:
            prefs_content = ""

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    # 2. VLM Verification Strategy
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available."}

    # Prompt for the VLM
    prompt = """
    You are verifying an Android navigation task. The user wants to DISABLE 3D Buildings/Landmarks in Sygic GPS.
    
    Analyze the sequence of screenshots.
    1. Did the user open the Settings menu?
    2. Did the user navigate to 'Map', 'Display', or 'View' settings?
    3. Did the user locate a toggle for '3D Buildings', 'Landmarks', or 'Building footprints'?
    4. Did the user toggle this setting to OFF (unchecked/gray)?
    
    Also look at the FINAL screenshot:
    5. Does the setting appear DISABLED in the final state?
    OR
    6. If the final screen is the map, does it look like 3D buildings are hidden?
    
    Return JSON:
    {
        "settings_opened": boolean,
        "correct_submenu_found": boolean,
        "building_toggle_seen": boolean,
        "toggle_switched_off": boolean,
        "final_state_correct": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
    
    # 3. Scoring Logic
    score = 0
    feedback = []
    
    if not vlm_response.get('success'):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to process images."}
        
    analysis = vlm_response.get('parsed', {})
    
    # Criterion 1: App Running (10 pts)
    if result_data.get('app_was_running', False):
        score += 10
    else:
        feedback.append("App was not running at the end.")

    # Criterion 2: Navigation (30 pts)
    if analysis.get('settings_opened'):
        score += 15
        if analysis.get('correct_submenu_found'):
            score += 15
    else:
        feedback.append("Did not navigate to Settings.")

    # Criterion 3: Identification & Action (60 pts)
    if analysis.get('building_toggle_seen'):
        score += 10
        if analysis.get('toggle_switched_off'):
            score += 30
            feedback.append("Successfully disabled 3D buildings.")
        elif analysis.get('final_state_correct'):
             # Sometimes we miss the toggle action but see the final state is correct
            score += 30
            feedback.append("Final state confirms buildings disabled.")
        else:
            feedback.append("Found the setting but failed to disable it.")
    else:
        # Backup: Check prefs text if VLM missed the visual toggle
        # Look for XML like <boolean name="show_buildings" value="false" />
        if "buildings" in prefs_content.lower() and "false" in prefs_content.lower():
            score += 40
            feedback.append("Internal preferences confirm setting is disabled.")
        elif analysis.get('final_state_correct'):
             # If VLM thinks final state looks correct even if it missed the toggle
            score += 20
            feedback.append("Visual state appears correct.")
        else:
            feedback.append("Could not verify that the '3D Buildings' setting was found or modified.")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": analysis
    }