#!/usr/bin/env python3
"""
Verifier for configure_shift task.

Verifies that a new shift record "Early Bird" was created with correct start/end times.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
try:
    from vlm_utils import query_vlm, get_final_screenshot, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_shift(traj, env_info, task_info):
    """
    Verify the agent created the 'Early Bird' shift definition.
    
    Scoring:
    - Shift record exists in DB: 60 points
    - Start time is correct (05:00 AM): 15 points
    - End time is correct (10:00 AM): 15 points
    - App was running/workflow evidence: 10 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if Shift Exists (60 pts)
    shift_exists = result.get('shift_exists', False)
    if shift_exists:
        score += 60
        feedback_parts.append("Shift 'Early Bird' created in database")
    else:
        feedback_parts.append("Shift 'Early Bird' NOT found in database")
        
    # 2. Check Times (15 + 15 pts)
    # Only check times if the shift exists
    if shift_exists:
        if result.get('start_time_match', False):
            score += 15
            feedback_parts.append("Start time correct (05:00 AM)")
        else:
            feedback_parts.append("Start time incorrect")
            
        if result.get('end_time_match', False):
            score += 15
            feedback_parts.append("End time correct (10:00 AM)")
        else:
            feedback_parts.append("End time incorrect")
    
    # 3. Process/App Check (10 pts)
    # If the app was running at the end OR we have DB success (implying app was used), give points
    if result.get('app_was_running', False) or shift_exists:
        score += 10
        feedback_parts.append("Application workflow verified")
        
    # VLM Verification (Bonus/Validation)
    # If DB check failed but we have screenshots, check via VLM to see if they tried
    if not shift_exists and VLM_AVAILABLE:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            Does this screen show a list of Shifts in a POS system? 
            Do you see a shift named "Early Bird" in the list?
            """
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                # If VLM sees it but DB didn't find it, maybe they didn't save?
                if "Early Bird" in vlm_res.get('response', '') or parsed.get('early_bird_visible', False):
                    feedback_parts.append("VLM saw 'Early Bird' in UI, but database record was missing (did you save?)")

    passed = score >= 90  # Strict pass: Record + Times must be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }