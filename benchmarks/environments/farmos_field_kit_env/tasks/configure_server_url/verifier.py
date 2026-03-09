#!/usr/bin/env python3
"""
Verifier for configure_server_url task.

Strategy:
1. Verify app is open (Basic)
2. Verify UI elements contain expected text (Programmatic via UI Dump)
   - Checks for URL "https://farm.extension.edu"
   - Checks for Username "field_educator"
   - Checks for Password field presence
3. VLM Verification (Robustness)
   - Visually confirms the fields are filled correctly
   - Catch cases where UI dump is incomplete (common in hybrid apps)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Mock for testing if not available
    def query_vlm(prompt, image):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None

def verify_configure_server_url(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_url = metadata.get('expected_url', 'https://farm.extension.edu')
    expected_username = metadata.get('expected_username', 'field_educator')
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check App State (10 points)
    if result_data.get("app_in_foreground", False):
        score += 10
        feedback_parts.append("App is open")
    else:
        feedback_parts.append("App is NOT open")

    # 3. Analyze UI Dump (Primary Programmatic Check) (40 points)
    # We fetch the XML content to regex search it
    ui_dump_content = ""
    if result_data.get("ui_dump_exists", False):
        temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/sdcard/ui_dump.xml", temp_xml.name)
            with open(temp_xml.name, 'r', errors='ignore') as f:
                ui_dump_content = f.read()
        except Exception:
            pass
        finally:
            if os.path.exists(temp_xml.name):
                os.unlink(temp_xml.name)

    # Check for URL
    url_found_in_dump = expected_url in ui_dump_content or "farm.extension.edu" in ui_dump_content
    if url_found_in_dump:
        score += 20
        feedback_parts.append("URL detected in UI dump")
    
    # Check for Username
    username_found_in_dump = expected_username in ui_dump_content
    if username_found_in_dump:
        score += 20
        feedback_parts.append("Username detected in UI dump")

    # 4. VLM Verification (Secondary/Fallback) (50 points)
    # Necessary because UI dumps in Hybrid apps (Cordova) can sometimes be empty/opaque
    final_screenshot = get_final_screenshot(traj)
    
    # If UI dump failed to find text, we rely heavily on VLM
    vlm_prompt = f"""
    Analyze this screenshot of the farmOS Field Kit mobile app login/configuration screen.
    
    I need to verify if the user has entered specific configuration details:
    1. Server URL field should contain "{expected_url}" (or part of it like "farm.extension.edu").
    2. Username field should contain "{expected_username}".
    3. Password field should have content (dots/asterisks/text).
    4. There should be NO error dialog visible.
    
    Return JSON:
    {{
        "url_correct": boolean,
        "username_correct": boolean,
        "password_filled": boolean,
        "error_visible": boolean,
        "reasoning": "string"
    }}
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # URL Logic
        if not url_found_in_dump:
            if parsed.get("url_correct", False):
                score += 20
                feedback_parts.append("URL verified visually")
            else:
                feedback_parts.append("URL not found in UI or Screenshot")
        
        # Username Logic
        if not username_found_in_dump:
            if parsed.get("username_correct", False):
                score += 20
                feedback_parts.append("Username verified visually")
            else:
                feedback_parts.append("Username not found in UI or Screenshot")
                
        # Password Logic (10 points) - VLM is best for this as dump masks it
        if parsed.get("password_filled", False):
            score += 10
            feedback_parts.append("Password field filled")
        else:
            feedback_parts.append("Password field appears empty")
            
        # Error Logic
        if parsed.get("error_visible", False):
            score -= 10
            feedback_parts.append("Error dialog visible (deduction)")
            
    else:
        feedback_parts.append("Visual verification failed (VLM error)")
        # Fallback scoring if VLM fails but UI dump worked
        if url_found_in_dump and username_found_in_dump:
             # Assume password was filled if others were correct to be charitable without VLM
             score += 10 

    # Calculate final result
    pass_threshold = metadata.get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }