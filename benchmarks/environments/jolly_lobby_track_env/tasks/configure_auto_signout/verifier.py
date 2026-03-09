#!/usr/bin/env python3
"""
Verifier for configure_auto_signout task.

Verification Strategy:
1. Anti-Gaming (File System): Check if configuration files/database were modified during the task.
2. Visual Verification (VLM): Analyze trajectory and final screenshot to confirm:
   - User navigated to Settings/Administration.
   - User enabled "Auto Sign Out".
   - User set the value to "8 hours" or "480 minutes".
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Import VLM utilities from the environment
# (Assuming gym_anything.vlm provides these, standard in this framework)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_auto_signout(traj, env_info, task_info):
    """
    Verify that the agent configured the auto-signout timer correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load File System Evidence
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Configuration Persistence (30 points) ---
    # Did the agent actually save changes?
    modified_files = result.get('modified_files', [])
    config_match = result.get('config_content_match', False)
    
    if modified_files:
        score += 30
        feedback_parts.append("Configuration files were updated successfully.")
        logger.info(f"Modified files detected: {modified_files}")
    else:
        feedback_parts.append("No configuration changes detected on disk (Did you click Save?).")
        # Proceed with VLM check, but max score is limited if nothing was saved

    # --- Criterion 2: Visual Verification (70 points) ---
    # Since we can't easily parse the binary database for the exact int value,
    # we rely heavily on VLM to "read" the UI state.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
         return {"passed": False, "score": score, "feedback": "No visual evidence available."}

    # Prepare VLM Prompt
    images_to_check = frames + [final_shot]
    
    prompt = """
    You are verifying if an agent successfully configured the 'Auto Sign Out' setting in Jolly Lobby Track.
    
    Review the screenshots. Look for a 'Settings', 'Options', or 'Administration' window.
    
    Answer the following questions:
    1. Is a settings or configuration dialog visible?
    2. Is the 'Auto Sign Out' (or similar 'Sign Out' / 'Check Out') checkbox ENABLED/CHECKED?
    3. Is the time duration set to '8' (hours) OR '480' (minutes)?
    4. Did the agent click 'Save' or 'OK' (visible in trajectory)?
    
    Respond in JSON:
    {
        "settings_opened": boolean,
        "feature_enabled": boolean,
        "correct_value_set": boolean,
        "saved_changes": boolean,
        "observed_value": "string or null",
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=images_to_check, prompt=prompt)
    
    if vlm_result.get('success'):
        analysis = vlm_result.get('parsed', {})
        
        # Sub-score: Found Settings (10 pts)
        if analysis.get('settings_opened'):
            score += 10
            feedback_parts.append("Navigated to settings.")
        
        # Sub-score: Enabled Feature (20 pts)
        if analysis.get('feature_enabled'):
            score += 20
            feedback_parts.append("Auto sign-out feature enabled.")
        else:
            feedback_parts.append("Auto sign-out feature NOT enabled.")

        # Sub-score: Correct Value (20 pts)
        if analysis.get('correct_value_set'):
            score += 20
            feedback_parts.append("Correct duration (8 hours/480 mins) set.")
        else:
            observed = analysis.get('observed_value', 'unknown')
            feedback_parts.append(f"Incorrect duration set (Observed: {observed}).")

        # Sub-score: Saved (20 pts)
        # We give credit if VLM sees the save action OR if files were modified
        if analysis.get('saved_changes') or modified_files:
            # Avoid double counting if we already gave points for file mods?
            # Actually, let's treat file mods as the 'hard' proof of saving (30pts above)
            # and this as 'soft' proof.
            # We'll just add remaining points to reach 100 if everything aligns.
            pass
            
    else:
        feedback_parts.append(f"Visual verification failed: {vlm_result.get('error')}")

    # Final scoring logic
    # Total possible so far: 30 (files) + 10 (nav) + 20 (enable) + 20 (value) = 80
    # Add 20 points for 'perfect alignment' (Files changed AND VLM says saved/correct)
    if modified_files and analysis.get('correct_value_set'):
        score += 20
    
    # Pass Threshold
    passed = score >= 70 and analysis.get('correct_value_set')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }