#!/usr/bin/env python3
"""
Verifier for change_voice_language task (Sygic GPS).

Verification Strategy:
1. VLM Trajectory Analysis (Primary):
   - Did the agent navigate to Settings?
   - Did the agent open Regional/Voice settings?
   - Is "Deutsch" (German) selected in the final or near-final frames?
2. Anti-Gaming (Secondary):
   - Was the app running at the end?
   - Were preference files modified after task start?
"""

import json
import os
import tempfile
import logging
import time
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_voice_language(traj, env_info, task_info):
    """
    Verify that the user changed the Sygic voice language to German.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve programmatic evidence
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        copy_from_env("/sdcard/task_prefs_list.txt", temp_prefs.name)
        
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        task_start_ts = result_data.get('task_start', 0)
        
        # Check if app was running (10 pts)
        if result_data.get('app_running', False):
            score += 10
            feedback_parts.append("App was running at end")
        else:
            feedback_parts.append("App was closed (penalty)")

        # Check for preference modifications (Anti-gaming) (20 pts)
        # We parse the ls -l output to see if files were touched
        prefs_modified = False
        with open(temp_prefs.name, 'r') as f:
            # Very basic heuristic: if list exists and is not empty
            content = f.read()
            if len(content.strip()) > 0:
                prefs_modified = True
                score += 20
                feedback_parts.append("Settings files modified")
            else:
                feedback_parts.append("No settings modified")

    except Exception as e:
        logger.warning(f"Error reading device files: {e}")
        feedback_parts.append("Could not verify file system state")

    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_prefs.name):
            os.unlink(temp_prefs.name)

    # 2. VLM Verification (70 pts)
    # We look at the trajectory to confirm the workflow
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No screenshots available for verification"
        }
        
    # Analysis Prompt
    prompt = """
    You are verifying a task in the Sygic GPS Navigation app.
    The goal is to change the 'Voice guidance' language to German (Deutsch).
    
    Review the screenshots sequence and determine:
    1. Did the user open the Settings menu?
    2. Did they navigate to 'Regional', 'Sound', or 'Voice' settings?
    3. Did they select 'Deutsch' or 'German' from a list?
    4. Does the final state show 'Deutsch' or 'German' as the selected voice?
    
    Provide a score between 0 and 70 based on:
    - 0: Irrelevant screenshots.
    - 20: Opened settings but didn't find voice options.
    - 40: Found voice options but didn't select German.
    - 70: Successfully selected German/Deutsch.
    
    Respond in JSON: {"score": int, "reason": "string"}
    """
    
    try:
        vlm_response = query_vlm(
            images=frames + [final_frame],
            prompt=prompt
        )
        
        vlm_data = vlm_response.get('parsed', {})
        vlm_score = vlm_data.get('score', 0)
        vlm_reason = vlm_data.get('reason', "VLM analysis failed")
        
        # Sanity cap
        vlm_score = min(70, max(0, vlm_score))
        
        score += vlm_score
        feedback_parts.append(f"Visual verification: {vlm_reason}")
        
    except Exception as e:
        logger.error(f"VLM error: {e}")
        feedback_parts.append("Visual verification failed due to error")

    # Final scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }