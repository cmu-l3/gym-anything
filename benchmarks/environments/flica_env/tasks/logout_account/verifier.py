#!/usr/bin/env python3
"""
Verifier for logout_account task.

Criteria:
1. App must still be installed (prevent uninstall gaming).
2. App must be running (prevent crash/force-close gaming).
3. UI must NOT show "Friends" page elements.
4. UI MUST show "Login" / "Welcome" elements.
5. VLM confirms visual state matches login screen.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logout_account(traj, env_info, task_info):
    """
    Verify the agent successfully logged out of Flight Crew View.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json_path = temp_json.name
    temp_json.close()

    try:
        # 1. Retrieve result JSON from device
        try:
            copy_from_env("/sdcard/task_result.json", temp_json_path)
            with open(temp_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task result: {str(e)}"
            }

        score = 0
        feedback_parts = []
        
        # --- Check 1: App Integrity (25 pts) ---
        if not result.get("app_installed", False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "FAILED: App was uninstalled. This is considered gaming."
            }
        
        if result.get("app_running", False):
            score += 15
            feedback_parts.append("App is running (+15)")
        else:
            feedback_parts.append("App is NOT running (crash?) (0)")
            
        if result.get("app_installed", False):
            score += 10
            feedback_parts.append("App installed (+10)")

        # --- Check 2: UI State via XML Dump (60 pts) ---
        login_found = result.get("login_indicators_found", False)
        friends_found = result.get("friends_indicators_found", False)

        if login_found:
            score += 35
            feedback_parts.append("Login screen detected (+35)")
        else:
            feedback_parts.append("Login screen NOT detected (0)")

        if not friends_found:
            score += 25
            feedback_parts.append("Friends page cleared (+25)")
        else:
            feedback_parts.append("Friends page still visible (0)")

        # --- Check 3: VLM Verification (15 pts) ---
        # We check if the visual state confirms logout
        final_screenshot = get_final_screenshot(traj)
        vlm_passed = False
        
        if final_screenshot:
            prompt = """
            You are verifying if a user has logged out of an app.
            Look at this screenshot.
            1. Do you see a Login screen, Welcome screen, or "Create Account" options?
            2. Do you see a list of friends or a "Friends" header (which would mean they are NOT logged out)?
            
            Answer JSON: {"is_login_screen": bool, "is_friends_screen": bool, "reason": "str"}
            """
            
            try:
                vlm_response = query_vlm(
                    images=[final_screenshot], 
                    prompt=prompt
                )
                
                parsed = vlm_response.get("parsed", {})
                is_login = parsed.get("is_login_screen", False)
                is_friends = parsed.get("is_friends_screen", False)
                
                if is_login and not is_friends:
                    score += 15
                    vlm_passed = True
                    feedback_parts.append("Visual verification passed (+15)")
                else:
                    feedback_parts.append(f"Visual verification failed: {parsed.get('reason', 'Unknown')}")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                feedback_parts.append("VLM check skipped (error)")
        
        # --- Final Scoring ---
        # Pass threshold: 60 points AND verified logout state
        # Must have at least: App running + Login detected + Friends gone = 15+35+25 = 75
        
        state_verified = login_found and not friends_found
        passed = (score >= 60) and state_verified
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        if os.path.exists(temp_json_path):
            os.remove(temp_json_path)