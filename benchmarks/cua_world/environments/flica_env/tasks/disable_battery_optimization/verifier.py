#!/usr/bin/env python3
"""
Verifier for disable_battery_optimization task.

Verifies that the agent correctly navigated Android settings to exempt
Flight Crew View from battery optimization.

Scoring Criteria:
1. System State (50 pts): Package appears in `dumpsys deviceidle whitelist`
2. Permissions (20 pts): `RUN_ANY_IN_BACKGROUND` is allowed
3. Trajectory (15 pts): Settings app appears in recent tasks history
4. Visual (15 pts): VLM confirms trajectory shows battery settings interaction
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_battery_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Android environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve/parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Criteria
    
    # CRITERION 1: Whitelist Check (50 pts) - The definitive check
    is_whitelisted = result.get('is_whitelisted', False)
    if is_whitelisted:
        score += 50
        feedback_parts.append("✅ App successfully added to battery optimization whitelist")
    else:
        feedback_parts.append("❌ App NOT found in battery whitelist")

    # CRITERION 2: App Ops Background Check (20 pts)
    bg_allowed = result.get('bg_ops_allowed', False)
    if bg_allowed:
        score += 20
        feedback_parts.append("✅ Background operations explicitly allowed")
    elif is_whitelisted:
        # Whitelisting implicitly allows this, so give partial credit if strictly query failed
        score += 20 
        feedback_parts.append("✅ Background operations allowed via whitelist")
    else:
        feedback_parts.append("❌ Background operations restricted")

    # CRITERION 3: Settings Access Check (15 pts) - Anti-gaming
    settings_accessed = result.get('settings_accessed', False)
    if settings_accessed:
        score += 15
        feedback_parts.append("✅ Android Settings accessed")
    else:
        feedback_parts.append("⚠️ Settings app not found in recent history")

    # CRITERION 4: VLM Trajectory Verification (15 pts)
    # We check if the agent actually looked at battery settings
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of an Android user's workflow.
        The goal was to disable battery optimization for an app named 'Flight Crew View'.
        
        Look for:
        1. The Android 'Settings' app or 'App Info' screen.
        2. A menu item labeled 'Battery' or 'App battery usage'.
        3. Selection of 'Unrestricted' or 'Not optimized'.
        
        Reply JSON: {"found_battery_settings": bool, "found_unrestricted_option": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('found_battery_settings') or parsed.get('found_unrestricted_option'):
                    score += 15
                    feedback_parts.append("✅ Visual confirmation of battery settings interaction")
                else:
                    feedback_parts.append("ℹ️ Visual analysis did not confirm battery settings workflow")
            else:
                # If VLM fails, award points if Settings was accessed (fallback)
                if settings_accessed:
                    score += 15
                    feedback_parts.append("✅ (Fallback) Settings access confirmed via logs")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if settings_accessed:
                score += 15
    
    # 3. Determine Pass/Fail
    # Must be whitelisted to pass.
    passed = is_whitelisted and score >= 50
    
    if not is_whitelisted:
        score = min(score, 40) # Cap score if main goal failed
        feedback_parts.append("FAILED: App is still optimized/restricted.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }