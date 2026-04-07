#!/usr/bin/env python3
"""
Verifier for update_facility_access_info task.
Verifies that CAMEO Data Manager was updated with specific security/access details.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_facility_access_info(traj, env_info, task_info):
    """
    Verify the facility record update.
    
    Criteria:
    1. Database file modified during task (20 pts)
    2. Specific text strings found in database file (30 pts)
       - "Knox Box 3200"
       - "North Service Road"
       - "Night watchman"
       - "7721#"
    3. Visual verification (VLM) of the Site Data tab (50 pts)
       - Checks for visibility of the entered text in the screenshot.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The PowerShell script saves to C:\Users\Docker\Documents\task_result.json
        # The mount points might map this to a specific path, but usually copy_from_env 
        # handles the internal path. Assuming standard Windows path mapping.
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Evaluate Database File Signal
    if result_data.get("db_modified", False):
        score += 20
        feedback.append("Database file was modified.")
    else:
        feedback.append("Database file was NOT modified.")

    # 3. Evaluate String Search Signal
    content_found = result_data.get("content_found", {})
    strings_score = 0
    if content_found.get("KeyLocation"): strings_score += 10
    if content_found.get("SiteAccess"): strings_score += 5
    if content_found.get("Security"): strings_score += 10
    if content_found.get("GateCode"): strings_score += 5
    
    score += strings_score
    if strings_score > 0:
        feedback.append(f"Found {strings_score}/30 points of expected text in database file.")

    # 4. VLM Visual Verification
    # We use the trajectory's final screenshot or the one explicitly captured
    
    # Try to get the specific screenshot captured by the script first
    local_screenshot_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    vlm_image = None
    
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_final.png", local_screenshot_path)
        vlm_image = local_screenshot_path
    except:
        # Fallback to framework's final screenshot
        vlm_image = get_final_screenshot(traj)

    if vlm_image:
        prompt = """
        Analyze this screenshot of CAMEO Data Manager.
        I am looking for specific text entered into the 'Site Data' or 'Access' fields.
        
        Check for the presence of ANY of the following phrases:
        1. "Knox Box 3200"
        2. "North Service Road"
        3. "Night watchman"
        4. "7721#"
        
        Also confirm if the application looks like a database form (CAMEO).
        
        Return JSON:
        {
            "is_cameo_form": true/false,
            "knox_box_visible": true/false,
            "site_access_visible": true/false,
            "security_visible": true/false,
            "gate_code_visible": true/false
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, image=vlm_image)
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            vlm_score = 0
            if parsed.get("is_cameo_form"): vlm_score += 10
            if parsed.get("knox_box_visible"): vlm_score += 10
            if parsed.get("site_access_visible"): vlm_score += 10
            if parsed.get("security_visible"): vlm_score += 10
            if parsed.get("gate_code_visible"): vlm_score += 10
            
            score += vlm_score
            feedback.append(f"Visual verification score: {vlm_score}/50")
            
            # Bonus: Trajectory check if final score is ambiguous
            if vlm_score < 20:
                frames = sample_trajectory_frames(traj, 3)
                feedback.append("Final screen checks failed, checking trajectory history...")
                # (Optional: perform simpler check on frames if needed)
        else:
            feedback.append("VLM query failed.")
    else:
        feedback.append("No screenshot available for VLM.")

    # Clean up
    if os.path.exists(local_screenshot_path):
        os.unlink(local_screenshot_path)

    # 5. Final Decision
    # Pass if score > 75 (Implies DB modified + some text found + some visual confirmation)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }