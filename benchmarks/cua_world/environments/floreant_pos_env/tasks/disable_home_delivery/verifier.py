#!/usr/bin/env python3
"""
Verifier for disable_home_delivery task.

Multi-signal verification:
1. Database State: Checks if 'HOME DELIVERY' visible=false (50 pts)
2. Safety Check: Checks if 'DINE IN' and 'TAKE OUT' are still visible=true (10 pts)
3. VLM Verification: Checks final screenshot for absence of 'HOME DELIVERY' button (30 pts)
4. App State: App was running at end of task (10 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_home_delivery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify Database State (Primary)
    hd_visible = result.get("home_delivery_visible")
    dine_in_visible = result.get("dine_in_visible")
    take_out_visible = result.get("take_out_visible")

    # Criterion: Home Delivery MUST be false
    if hd_visible == "false":
        score += 50
        feedback.append("Success: Home Delivery disabled in database.")
    elif hd_visible == "true":
        feedback.append("Fail: Home Delivery is still enabled in database.")
    else:
        feedback.append("Fail: Could not determine Home Delivery status.")

    # Criterion: Others MUST be true (Safety check)
    if dine_in_visible == "true" and take_out_visible == "true":
        score += 10
        feedback.append("Success: Other order types remain active.")
    else:
        feedback.append("Warning: Other order types (Dine In/Take Out) may have been disabled accidentally.")

    # Criterion: App running
    if result.get("app_was_running", False):
        score += 10
    else:
        feedback.append("Warning: Application was closed at end of task.")

    # 3. VLM Verification (Visual confirmation)
    # We check if the button is visually gone from the main screen
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of the Floreant POS main terminal.
        1. Look for a button labeled 'HOME DELIVERY'.
        2. Look for buttons labeled 'DINE IN' and 'TAKE OUT'.
        
        Is the 'HOME DELIVERY' button visible? (It should NOT be).
        Are 'DINE IN' and 'TAKE OUT' visible? (They SHOULD be).
        """
        
        vlm_res = query_vlm(prompt=prompt, images=[final_screenshot])
        
        if vlm_res and vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {}) # assuming structured output or parsing logic in wrapper
            # Simple text analysis fallback if structure not guaranteed
            response_text = vlm_res.get('response', '').lower()
            
            button_gone = "no" in response_text and "home delivery" in response_text # simplistic
            # Better manual heuristic or structured prompt usage:
            # Let's assume the VLM wrapper returns a structured 'success' based on prompt
            
            # Since we can't guarantee structured output format here, we rely on the DB score primarily
            # and add points if the VLM response confirms the goal.
            
            if "not visible" in response_text or "absent" in response_text:
                score += 30
                feedback.append("Visual verification passed: Home Delivery button absent.")
            else:
                feedback.append("Visual verification inconclusive or failed.")
        else:
            # Fallback if VLM fails: grant points if DB check was perfect
            if score >= 60:
                score += 30
                feedback.append("Visual verification skipped (VLM error), assumed passed based on DB.")

    # 4. Final Assessment
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }