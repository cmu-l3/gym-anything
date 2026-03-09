#!/usr/bin/env python3
"""
Verifier for configure_facility_profile task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_facility_profile(traj, env_info, task_info):
    """
    Verify facility profile configuration using file evidence and VLM.
    
    Scoring:
    - Programmatic (50 pts):
        - Data found in modified files (Company: 20, Address: 10, Phone: 10)
        - Files modified during task (10)
    - VLM (50 pts):
        - Settings dialog visible in trajectory (15)
        - Form fields populated correctly (15)
        - Final screen shows company name (20)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Programmatic Checks (50 pts) ---
    data = result.get('data_found', {})
    
    if data.get('company', False):
        score += 20
        feedback.append("Company name found in configuration/DB files (+20)")
    else:
        feedback.append("Company name NOT found in files")

    if data.get('address', False) and data.get('zip', False):
        score += 10
        feedback.append("Address details found in files (+10)")
    
    if data.get('phone', False):
        score += 10
        feedback.append("Phone number found in files (+10)")

    if result.get('config_files_modified', False):
        score += 10
        feedback.append("Configuration files modified during task (+10)")
    else:
        feedback.append("No configuration files were modified (did you save?)")

    # --- VLM Verification (50 pts) ---
    # We need to verify the PROCESS (opening settings) and the VISUAL OUTCOME (name on screen)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for the VLM
    prompt = """
    You are verifying an agent configuring 'Lobby Track' software.
    The goal was to set the Company Name to 'Greenfield Medical Center' and update address/phone.

    Please analyze the screenshots (trajectory and final state):
    1. Do you see a Settings, Options, or Configuration dialog open in any frame?
    2. Do you see form fields filled with:
       - 'Greenfield Medical Center'
       - '450 Healthcare Drive'
       - '(503) 555-0142'
    3. In the final screenshot, is 'Greenfield Medical Center' visible on the main window title bar or header?

    Provide a JSON response:
    {
        "settings_opened": boolean,
        "fields_filled": boolean,
        "name_on_main_screen": boolean,
        "reasoning": "string"
    }
    """
    
    if query_vlm:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {})
            
            if analysis.get('settings_opened', False):
                score += 15
                feedback.append("VLM: Settings/Options dialog verified (+15)")
            
            if analysis.get('fields_filled', False):
                score += 15
                feedback.append("VLM: Data entry verified (+15)")
                
            if analysis.get('name_on_main_screen', False):
                score += 20
                feedback.append("VLM: Company name visible on main screen (+20)")
            else:
                feedback.append("VLM: Company name NOT found on main screen")
        else:
            feedback.append(f"VLM analysis failed: {vlm_res.get('error')}")
            # Fallback points if programmatic was perfect
            if score >= 40:
                score += 20
                feedback.append("VLM failed but data verified strongly (+20 fallback)")
    else:
        feedback.append("VLM not available")
    
    # Pass threshold
    passed = score >= 60 and data.get('company', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }