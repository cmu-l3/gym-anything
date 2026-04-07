#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_allow_cellular_downloads(traj, env_info, task_info):
    """
    Verifies that the agent disabled the 'Wi-Fi only' download restriction.
    
    Strategy:
    1. VLM Trajectory Analysis (Primary):
       - Confirm navigation to Settings.
       - Confirm identification of 'Wi-Fi only' toggle.
       - Confirm visual state change (Checked -> Unchecked).
    
    2. Preference File Diff (Secondary/Supporting):
       - Compare initial vs final grep of shared_prefs.
       - Look for keys like "wifi_only", "connection_settings" changing value.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 2. Get artifacts
    try:
        # Get result JSON
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env("/sdcard/task_result.json", f.name)
            with open(f.name) as jf:
                result_data = json.load(jf)
        
        # Get pref dumps
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f_init:
            copy_from_env("/sdcard/initial_prefs_dump.txt", f_init.name)
            with open(f_init.name, 'r') as fi:
                initial_prefs = fi.readlines()
                
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f_final:
            copy_from_env("/sdcard/final_prefs_dump.txt", f_final.name)
            with open(f_final.name, 'r') as ff:
                final_prefs = ff.readlines()
                
    except Exception as e:
        logger.error(f"Failed to copy/read artifacts: {e}")
        # Continue with VLM only if files fail, but penalize
        initial_prefs = []
        final_prefs = []
        feedback.append("Warning: Could not read internal app state.")

    # 3. Preference Analysis (Programmatic Check)
    # We are looking for a line that changed from true/1 to false/0 related to wifi
    pref_score = 0
    pref_change_detected = False
    
    # Simple heuristics for potential keys
    relevant_keywords = ["wifi", "only", "connection"]
    
    # Create set of stripped lines for comparison
    init_set = set(line.strip() for line in initial_prefs)
    final_set = set(line.strip() for line in final_prefs)
    
    # Find new lines (lines in final but not init)
    new_lines = final_set - init_set
    
    for line in new_lines:
        lower_line = line.lower()
        # Look for "false" or "0" or "off" in a line containing wifi
        if any(k in lower_line for k in relevant_keywords):
            if 'false' in lower_line or 'value="0"' in lower_line:
                pref_change_detected = True
                feedback.append(f"Detected preference change: {line}")
                break
    
    if pref_change_detected:
        pref_score = 40
        feedback.append("App configuration file confirms 'Wi-Fi only' restriction was disabled.")
    else:
        # It's possible the key didn't change format or we missed it, so we don't fail immediately,
        # but we rely more heavily on VLM.
        feedback.append("No definitive configuration file change detected (could be masked).")

    # 4. VLM Verification (Trajectory)
    # This is critical because pref keys are obfuscated/variable
    frames = sample_trajectory_frames(traj, n=6)
    final_shot = get_final_screenshot(traj)
    
    prompt = """
    You are verifying an agent acting on an Android GPS app.
    Goal: Disable 'Wi-Fi only' for map downloads (allow cellular downloads).
    
    Review the image sequence:
    1. Did the agent navigate to 'Settings'?
    2. Did the agent find a section for 'Map management', 'Connection', or 'Online'?
    3. Did the agent find a toggle labeled 'Wi-Fi only', 'Download on Wi-Fi only', or similar?
    4. Did the agent SWITCH the toggle from ON (usually highlighted/colored) to OFF (gray/dim)?
    
    Output JSON:
    {
        "settings_opened": true/false,
        "wifi_toggle_found": true/false,
        "toggle_switched_off": true/false,
        "final_state_correct": true/false,
        "confidence": 0-10
    }
    """
    
    vlm_response = query_vlm(
        images=frames + [final_shot],
        prompt=prompt
    )
    
    vlm_data = vlm_response.get('parsed', {})
    
    # Scoring VLM
    vlm_score = 0
    if vlm_data.get('settings_opened'):
        vlm_score += 10
    if vlm_data.get('wifi_toggle_found'):
        vlm_score += 20
    if vlm_data.get('toggle_switched_off'):
        vlm_score += 30
    
    score = pref_score + vlm_score
    
    # Sanity check: If VLM is super confident the toggle is OFF, pass even if prefs were obscure
    if vlm_data.get('final_state_correct') and vlm_data.get('confidence', 0) > 8:
        if score < 70:
            score = 70 # Boost to pass threshold
            feedback.append("VLM confirms visual success despite ambiguous file state.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }