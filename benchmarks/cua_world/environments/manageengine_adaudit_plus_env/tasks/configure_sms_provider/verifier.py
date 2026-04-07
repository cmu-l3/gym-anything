#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_sms_provider(traj, env_info, task_info):
    """
    Verify that the SMS provider settings were configured correctly.
    
    Verification Strategy:
    1. Basic: Check if files were modified in the app directory (implies save action).
    2. Visual (VLM): Analyze the final screenshot (or trajectory) to verify the filled form.
       - URL: https://api.bulksmsgateway.net/v2/send
       - Method: POST
       - Params: apiKey, sender, to, message
    """
    
    # 1. Retrieve result JSON from the environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The export script saves to C:\Windows\Temp\task_result.json
        # The copy_from_env tool needs to handle the Windows path or the container path mapping.
        # Assuming the framework handles the path conversion or we use the absolute path.
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Scoring Variables
    score = 0
    feedback = []
    
    # Criterion 1: Activity Detection (Files modified) (20 pts)
    # If the user saved settings, config files or logs should have updated.
    if result_data.get("files_modified_during_task", False):
        score += 20
        feedback.append("System activity detected (files modified).")
    else:
        feedback.append("No system activity detected (no files modified).")

    # Criterion 2: Browser State (10 pts)
    if result_data.get("browser_running", False):
        score += 10
    else:
        feedback.append("Browser was closed.")

    # Criterion 3: Visual Verification via VLM (70 pts)
    # We use the final screenshot to check the form state.
    
    final_screenshot = get_final_screenshot(traj)
    
    # If final screenshot is missing from trajectory, try to use the one exported by script
    # (But verify_task receives 'traj' which contains frames captured by the harness)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No visual evidence available."}

    vlm_prompt = """
    You are an IT auditor verifying a configuration task in ManageEngine ADAudit Plus.
    The user was asked to configure SMS Server Settings.
    
    Please examine the screenshot and verify the following:
    1. Is the "SMS Server Settings" or "SMS Provider" page visible?
    2. Is the "Gateway URL" set to 'https://api.bulksmsgateway.net/v2/send'?
    3. Is the HTTP Method set to 'POST'?
    4. Are the parameters configured? Look for:
       - apiKey: f8c3a9d1b7e24056be91dc3a47f6e8a0
       - sender: ADAuditSec
       - to: %mobile%
       - message: %message%
    
    Respond in JSON format:
    {
        "page_visible": boolean,
        "url_correct": boolean,
        "method_correct": boolean,
        "params_present": boolean,
        "save_success_message": boolean,
        "explanation": "string"
    }
    """
    
    vlm_response = query_vlm(
        prompt=vlm_prompt,
        images=[final_screenshot]
    )
    
    if vlm_response and vlm_response.get("success"):
        analysis = vlm_response.get("parsed", {})
        
        if analysis.get("page_visible"):
            score += 10
            feedback.append("SMS Settings page is visible.")
            
            if analysis.get("url_correct"):
                score += 20
                feedback.append("Gateway URL is correct.")
            else:
                feedback.append("Gateway URL incorrect or not visible.")
                
            if analysis.get("method_correct"):
                score += 10
                feedback.append("HTTP Method is correct.")
                
            if analysis.get("params_present"):
                score += 30
                feedback.append("Parameters appear to be configured correctly.")
            else:
                feedback.append("Parameters missing or incorrect.")
        else:
            feedback.append("SMS Settings page not found in final screenshot.")
    else:
        feedback.append("Visual verification failed (VLM error).")

    # Final Pass check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }