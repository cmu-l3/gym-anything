#!/usr/bin/env python3
"""
Verifier for configure_dashboard_widgets task.

Verification Strategy:
1. File Check: Verify 'dashboard_final.png' exists and was created during the task.
2. VLM Verification: Use VLM to analyze the screenshot for:
   - Presence of 'Logon Failure' widget
   - Presence of 'Account Lockout' widget
   - Absence of 'Getting Started' widget
   - Verification that the interface is ADAudit Plus
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dashboard_widgets(traj, env_info, task_info):
    """
    Verify the ADAudit Plus dashboard customization.
    """
    # 1. Setup and Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    # 2. Get Task Metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_screenshot_path', 'C:\\workspace\\dashboard_final.png')
    
    # 3. Retrieve Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 4. Retrieve Screenshot from Container
    local_screenshot_path = None
    if result_data.get("output_exists"):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        local_screenshot_path = temp_img.name
        temp_img.close() # Close so we can write to it via copy_from_env (or just use name)
        try:
            copy_from_env(expected_path, local_screenshot_path)
        except Exception as e:
            # If copy fails, treat as file not found
            local_screenshot_path = None
            logger.error(f"Failed to copy screenshot: {e}")

    # 5. Scoring Logic
    score = 0
    feedback_lines = []

    # Criterion A: Screenshot Exists & Created During Task (20 pts)
    if result_data.get("output_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_lines.append("Screenshot file created successfully.")
    elif result_data.get("output_exists"):
        score += 5
        feedback_lines.append("Screenshot exists but timestamp is invalid (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "No dashboard screenshot found at expected path."}

    # Criterion B: File Size Check (10 pts)
    # 50KB limit to avoid empty/black screenshots
    size_kb = result_data.get("output_size_bytes", 0) / 1024
    if size_kb > 50:
        score += 10
    else:
        feedback_lines.append(f"Warning: Screenshot is very small ({size_kb:.1f} KB).")

    # Criterion C: VLM Visual Verification (70 pts)
    if local_screenshot_path:
        from gym_anything.vlm import query_vlm # Mock import, assumes framework availability
        
        prompt = """
        You are verifying an IT Admin task in ManageEngine ADAudit Plus.
        The user was asked to customize the dashboard.

        Look at the screenshot and check for the following:
        1. Is this the ADAudit Plus Dashboard?
        2. Is there a widget visible related to "Logon Failures" (e.g., "Recent Logon Failures", "Failed Logons")?
        3. Is there a widget visible related to "Account Lockout" (e.g., "Locked Out Users", "Account Lockout Analyzer")?
        4. Is the default "Getting Started" or "Welcome" widget GONE (Not visible)?

        Respond in JSON format:
        {
            "is_adaudit_dashboard": boolean,
            "has_logon_failure_widget": boolean,
            "has_lockout_widget": boolean,
            "getting_started_removed": boolean,
            "explanation": "string"
        }
        """
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=local_screenshot_path)
            
            if vlm_response.get("success"):
                analysis = vlm_response.get("parsed", {})
                
                # Check 1: Is Dashboard (10 pts)
                if analysis.get("is_adaudit_dashboard"):
                    score += 10
                    feedback_lines.append("Verified ADAudit Plus dashboard interface.")
                
                # Check 2: Logon Failure Widget (25 pts)
                if analysis.get("has_logon_failure_widget"):
                    score += 25
                    feedback_lines.append("Found 'Logon Failure' widget.")
                else:
                    feedback_lines.append("Missing 'Logon Failure' widget.")

                # Check 3: Account Lockout Widget (25 pts)
                if analysis.get("has_lockout_widget"):
                    score += 25
                    feedback_lines.append("Found 'Account Lockout' widget.")
                else:
                    feedback_lines.append("Missing 'Account Lockout' widget.")
                
                # Check 4: Cleanup (10 pts)
                if analysis.get("getting_started_removed"):
                    score += 10
                    feedback_lines.append("'Getting Started' widget correctly removed.")
                else:
                    feedback_lines.append("'Getting Started' widget still present.")
                    
            else:
                feedback_lines.append("Visual verification failed to process image.")
                
        except Exception as e:
            feedback_lines.append(f"VLM verification error: {str(e)}")
            
        # Cleanup local file
        try:
            if os.path.exists(local_screenshot_path):
                os.unlink(local_screenshot_path)
        except:
            pass

    # Final Pass/Fail Determination
    # Threshold: 60 points (Need file + at least one correct widget or valid dashboard + file)
    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_lines)
    }