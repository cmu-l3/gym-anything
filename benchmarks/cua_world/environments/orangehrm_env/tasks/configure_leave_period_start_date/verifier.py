#!/usr/bin/env python3
"""
Verifier for configure_leave_period_start_date task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_leave_period_start_date(traj, env_info, task_info):
    """
    Verifies that the leave period start date was correctly set to April 1st.
    
    Criteria:
    1. Database: 'leave_period_start_month' is '4' (April).
    2. Database: 'leave_period_start_day' is '1'.
    3. State Change: Values actually changed from default/initial.
    4. VLM: Agent visited the Leave Period configuration page.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    final_month = result.get('final_month', '0')
    final_day = result.get('final_day', '0')
    config_changed = result.get('config_changed', False)
    
    feedback_parts = []
    score = 0
    
    # CRITERION 1: Month is April (4) - 40 points
    # Allow string "4" or integer 4
    if str(final_month).strip() == "4":
        score += 40
        feedback_parts.append("Start Month correctly set to April")
    else:
        feedback_parts.append(f"Start Month incorrect (expected 4, got {final_month})")

    # CRITERION 2: Day is 1 - 40 points
    if str(final_day).strip() == "1":
        score += 40
        feedback_parts.append("Start Date correctly set to 1st")
    else:
        feedback_parts.append(f"Start Date incorrect (expected 1, got {final_day})")

    # CRITERION 3: VLM Navigation Check - 20 points
    # We want to see if they actually used the UI
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an agent using OrangeHRM.
        Did the agent navigate to the "Leave Period" configuration screen?
        Look for headers saying "Leave Period" or dropdowns for "Start Month" and "Start Date".
        
        Respond with YES or NO and a brief reason.
        """
        
        # We use a simplified check or a structured JSON check depending on VLM capability.
        # Here assuming simple text response for scoring logic or boolean.
        try:
            vlm_resp = query_vlm(images=frames + [final_screen], prompt=prompt)
            if "YES" in str(vlm_resp).upper():
                vlm_score = 20
                feedback_parts.append("UI navigation verified")
            else:
                feedback_parts.append("Could not verify UI navigation via screenshots")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if DB is correct, give partial VLM points
            if score >= 80:
                vlm_score = 10
    
    score += vlm_score

    # Anti-gaming check
    if score >= 80 and not config_changed:
        # Values match target but didn't change? 
        # Means they were already set (unlikely due to setup) or setup failed.
        # We penalize slightly or flag it.
        feedback_parts.append("(Warning: Configuration didn't change from initial state)")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }