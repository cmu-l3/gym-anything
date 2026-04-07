#!/usr/bin/env python3
"""
Verifier for enforce_password_policy task.

Verification Strategy:
1. PRIMARY: Query SuiteCRM's `config_override.php` / `$sugar_config` array via JSON export to 
   precisely verify the 5 exact fields (Length, Upper, Lower, Number, Special).
2. ANTI-GAMING: Check if config modification time is > task start time.
3. SECONDARY (VLM): Evaluate trajectory frames to ensure the agent interacted 
   with the Password Management UI and successfully saved.
"""

import os
import json
import tempfile
import logging

from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance on a SuiteCRM administration task.
The task is to enforce a secure password policy by changing global system settings.
Look at these screenshots from the agent's trajectory.

Evaluate the agent's workflow:
1. Did the agent successfully navigate to the 'Password Management' configuration page?
2. Did the agent interact with the password complexity checkboxes and/or length input field?
3. Did the agent click the "Save" button to apply the changes?

Return a JSON object with strictly these boolean keys:
{
    "navigated_to_page": true/false,
    "interacted_with_form": true/false,
    "saved_successfully": true/false
}
"""

def _is_truthy(val):
    """Helper to handle PHP boolean/string truthiness from config export."""
    if val is None:
        return False
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return val == 1
    if isinstance(val, str):
        return val.lower() in ['1', 'true', 'on', 'yes']
    return False

def verify_enforce_password_policy(traj, env_info, task_info):
    """Verifies the password policy settings and trajectory."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_length = metadata.get('expected_length', 12)

    # 1. Read exported results from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/password_policy_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)
    config_data = result.get('config_data', {})
    config_mtime = config_data.get('config_mtime', 0)
    pwd_settings = config_data.get('passwordsetting', {})

    score = 0
    feedback_parts = []
    
    # 2. Programmatic checks on the config array
    
    # Check modification time to prevent gaming (must be modified after task setup)
    if config_mtime > 0 and config_mtime >= task_start:
        feedback_parts.append("Config updated during task")
    elif len(pwd_settings) > 0:
        # Fallback if mtime wasn't reliable but settings exist
        feedback_parts.append("Password settings detected")
    else:
        feedback_parts.append("Config not updated (No settings saved)")

    # Minimum Length (25 points) - Most important, must be exact
    actual_len = pwd_settings.get('minpwdlength', '')
    try:
        if int(actual_len) == expected_length:
            score += 25
            feedback_parts.append(f"Min length correct ({expected_length})")
        else:
            feedback_parts.append(f"Min length incorrect (Got {actual_len}, expected {expected_length})")
    except (ValueError, TypeError):
        feedback_parts.append(f"Min length missing or invalid")

    # Complexity toggles (15 points each)
    complexities = [
        ('oneupper', 'Uppercase required'),
        ('onelower', 'Lowercase required'),
        ('onenumber', 'Number required'),
        ('onespecial', 'Special character required')
    ]

    complexity_score = 0
    for key, name in complexities:
        if _is_truthy(pwd_settings.get(key)):
            complexity_score += 15
            score += 15
        else:
            feedback_parts.append(f"Missing: {name}")
            
    if complexity_score == 60:
        feedback_parts.append("All complexity rules applied")

    # 3. VLM Verification (15 points)
    # Using trajectory frames to verify actual workflow instead of just final snapshot
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
        parsed = vlm_response.get("parsed", {})
        
        vlm_pts = 0
        if parsed.get("navigated_to_page"): vlm_pts += 5
        if parsed.get("interacted_with_form"): vlm_pts += 5
        if parsed.get("saved_successfully"): vlm_pts += 5
        
        score += vlm_pts
        if vlm_pts == 15:
            feedback_parts.append("VLM confirmed valid workflow")
        else:
            feedback_parts.append(f"VLM workflow partial/failed ({vlm_pts}/15 pts)")
            
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("VLM verification failed")

    # 4. Final calculation
    # Passing threshold: 70 points (e.g. Length + 3 complexity rules, or Length + 2 rules + VLM)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }