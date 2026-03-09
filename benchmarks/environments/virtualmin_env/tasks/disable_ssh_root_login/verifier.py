#!/usr/bin/env python3
"""
Verifier for disable_ssh_root_login task.

Verification Strategy:
1. Programmatic Check (Primary):
   - Is 'permitrootlogin no' active in the running sshd process? (sshd -T)
   - Is the sshd_config file updated correctly?
   - Was the file modified during the task window?
   
2. VLM Verification (Secondary):
   - Did the agent navigate through the Webmin UI?
   - Does the final screenshot show the SSH Server module?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_ssh_root_login(traj, env_info, task_info):
    """
    Verify that SSH root login has been disabled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Load Result JSON from Container
    # ================================================================
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

    # ================================================================
    # 2. Programmatic Verification (75 points total)
    # ================================================================
    
    # Criterion A: Runtime Configuration (40 points)
    # This is the most important: is the server actually secure right now?
    if result.get("runtime_config_correct", False):
        score += 40
        feedback_parts.append("SSH runtime configuration is correct (Root login disabled).")
    else:
        feedback_parts.append("SSH runtime configuration is INCORRECT (Root login still allowed).")

    # Criterion B: File Configuration (20 points)
    # Did they save the file correctly?
    if result.get("file_config_correct", False):
        score += 20
        feedback_parts.append("Configuration file updated correctly.")
    else:
        feedback_parts.append("Configuration file does not match expected state.")

    # Criterion C: Anti-Gaming / Work Done (15 points)
    # Did they actually modify the file during the task?
    if result.get("config_modified_during_task", False):
        score += 15
        feedback_parts.append("Configuration modified during task window.")
    else:
        feedback_parts.append("Configuration file was NOT modified during the task.")

    # Criterion D: Service Health (10 points deduction if broken)
    # If they broke SSH entirely, that's bad.
    if not result.get("service_running", False):
        score = max(0, score - 20)
        feedback_parts.append("CRITICAL: SSH service is not running.")

    # ================================================================
    # 3. VLM Verification (25 points)
    # ================================================================
    # We want to confirm they used the Webmin UI as requested
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a task where an agent must disable SSH root login using the Webmin interface.
    
    Review the screenshots (chronological order) and determine:
    1. Did the agent navigate to the Webmin 'SSH Server' module?
    2. Did the agent access the 'Authentication' settings?
    3. Is there visual evidence of changing 'Allow login by root' to 'No'?
    
    Respond in JSON:
    {
        "webmin_ssh_accessed": true/false,
        "authentication_settings_seen": true/false,
        "setting_changed": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        
        vlm_score = 0
        if parsed.get("webmin_ssh_accessed", False):
            vlm_score += 10
        if parsed.get("authentication_settings_seen", False):
            vlm_score += 10
        if parsed.get("setting_changed", False):
            vlm_score += 5
            
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append(f"Visual verification confirmed UI usage (+{vlm_score} pts).")
        else:
            feedback_parts.append("Visual verification could not confirm Webmin UI usage.")
            
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback: if programmatic passed, give partial VLM points
        if score >= 60:
            score += 10
            feedback_parts.append("VLM check skipped, awarding partial points based on programmatic success.")

    # ================================================================
    # 4. Final Scoring
    # ================================================================
    
    # Key criteria: Runtime config must be correct OR file config correct + modified
    # (Sometimes runtime update fails if service restart fails, but if file is right, it's partial success)
    key_criteria_met = result.get("runtime_config_correct", False) or \
                       (result.get("file_config_correct", False) and result.get("config_modified_during_task", False))

    final_result = {
        "passed": score >= 75 and key_criteria_met,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }
    
    return final_result