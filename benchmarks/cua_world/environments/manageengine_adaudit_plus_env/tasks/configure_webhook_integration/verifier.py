#!/usr/bin/env python3
"""
Verifier for configure_webhook_integration task.

Uses a hybrid approach:
1. Checks if the agent created the configuration (via export_result.ps1 analysis).
2. Uses VLM to verify the UI state from the final screenshot, ensuring specific values are correct.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_webhook_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_profile = metadata.get('profile_name', 'SOAR_Integration')
    expected_url = metadata.get('target_url')
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Note: export_result.ps1 saves to C:\workspace\tasks\task_result.json
        # Container path mapping might vary, assuming standard location based on env
        copy_from_env("C:\\workspace\\tasks\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. VLM Verification (Primary for UI-based tasks where DB access is tricky)
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    vlm_feedback = ""
    
    if final_screenshot and os.path.exists(final_screenshot):
        prompt = f"""
        Analyze this screenshot of the ManageEngine ADAudit Plus Webhook configuration.
        
        I am looking for a Webhook Profile with these specific settings:
        1. Profile Name: "{expected_profile}"
        2. URL: "{expected_url}" (or part of it like 'soar-api.corp.local')
        3. Method: POST
        4. Headers: x-api-key
        5. Payload Type: JSON
        
        Respond in JSON with these boolean keys:
        - profile_visible: true if the profile list or details shows '{expected_profile}'
        - url_correct: true if the URL is visible and matches
        - header_visible: true if the header key/value is visible
        - payload_json: true if JSON format is selected or visible in body
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('profile_visible'): vlm_score += 25
            if parsed.get('url_correct'): vlm_score += 25
            if parsed.get('header_visible'): vlm_score += 20
            if parsed.get('payload_json'): vlm_score += 10
            
            vlm_feedback = f"VLM Analysis: {parsed}"
        except Exception as e:
            vlm_feedback = f"VLM Error: {str(e)}"
    else:
        vlm_feedback = "No screenshot available for VLM verification."

    # 3. Config File Verification (Secondary/Backup)
    file_score = 0
    if result_data.get('config_found_in_files'):
        file_score += 20 # Bonus confidence if found in files
    
    # Combine Scores
    # We weight VLM higher because we want to see the UI confirmation, 
    # but file evidence helps if UI is partial.
    total_score = min(100, vlm_score + file_score)
    
    # Pass logic: Must have profile visible and reasonable URL/settings
    passed = total_score >= 60 and (result_data.get('config_found_in_files') or parsed.get('profile_visible', False))

    return {
        "passed": passed,
        "score": total_score,
        "feedback": f"{vlm_feedback}. File Evidence: {result_data.get('config_found_in_files')}"
    }