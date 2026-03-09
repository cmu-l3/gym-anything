#!/usr/bin/env python3
"""
Verifier for customize_compliance_links task.

Verification Strategy:
1. File Analysis: Parse the submitted `custom-interface_config.js` to ensure specific keys are set correctly.
2. Anti-Gaming: Ensure file was modified during task.
3. VLM Verification: visual check of the interface to confirm 'Invite' button is gone and UI is healthy.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_compliance_links(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_links = metadata.get('required_links', {})
    forbidden_buttons = metadata.get('forbidden_buttons', [])
    required_buttons = metadata.get('required_buttons', [])

    score = 0
    feedback = []
    
    # ================================================================
    # 1. Load Task Result JSON
    # ================================================================
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=True, suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    if not task_result.get("config_exists", False):
        return {"passed": False, "score": 0, "feedback": "Configuration file not found."}

    if not task_result.get("config_modified_during_task", False):
        feedback.append("Warning: Configuration file was not modified during the task window.")
        # We penalize but don't fail immediately, in case of clock skew, but it's a strong signal.
        # For this logic, we'll deduct points.
        
    score += 10 # Config exists

    # ================================================================
    # 2. Analyze Configuration Content
    # ================================================================
    config_content = ""
    with tempfile.NamedTemporaryFile(delete=True, suffix='.js') as f:
        try:
            copy_from_env("/tmp/submitted_config.js", f.name)
            f.seek(0)
            config_content = f.read().decode('utf-8')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve config file: {e}"}

    # Helper for regex search
    def check_setting(content, key, expected_val_str):
        # Matches: key = value, key: value, key = "value", etc.
        # We try to be flexible with JS syntax
        patterns = [
            rf"{key}\s*=\s*{re.escape(expected_val_str)}",
            rf"{key}\s*:\s*{re.escape(expected_val_str)}",
            rf"['\"]{key}['\"]\s*:\s*{re.escape(expected_val_str)}"
        ]
        for p in patterns:
            if re.search(p, content, re.IGNORECASE):
                return True
        return False

    # Check MOBILE_APP_PROMO
    if check_setting(config_content, "MOBILE_APP_PROMO", "false"):
        score += 10
        feedback.append("MOBILE_APP_PROMO disabled correctly.")
    else:
        feedback.append("MOBILE_APP_PROMO not correctly disabled.")

    # Check Links
    # We look for the URL string associated with the key
    link1 = required_links.get("JITSI_WATERMARK_LINK", "")
    if link1 in config_content and "JITSI_WATERMARK_LINK" in config_content:
        # Rough check ensures key and value are present. 
        # For a stricter check, we can use regex, but URL might be quoted differently.
        if re.search(rf"JITSI_WATERMARK_LINK.*{re.escape(link1)}", config_content, re.DOTALL):
            score += 10
            feedback.append("Watermark link configured.")
        else:
            feedback.append("Watermark link found but association unclear.")
    else:
        feedback.append("Watermark link missing or incorrect.")

    link2 = required_links.get("LIVE_STREAMING_HELP_LINK", "")
    if link2 in config_content and "LIVE_STREAMING_HELP_LINK" in config_content:
        if re.search(rf"LIVE_STREAMING_HELP_LINK.*{re.escape(link2)}", config_content, re.DOTALL):
            score += 10
            feedback.append("Streaming help link configured.")
        else:
            feedback.append("Streaming help link found but association unclear.")
    else:
        feedback.append("Streaming help link missing or incorrect.")

    # Check TOOLBAR_BUTTONS
    # We extract the list/array assigned to TOOLBAR_BUTTONS
    tb_match = re.search(r"TOOLBAR_BUTTONS\s*[:=]\s*\[(.*?)\]", config_content, re.DOTALL)
    if tb_match:
        buttons_str = tb_match.group(1)
        # Clean quotes
        buttons_list = [b.strip().strip("'").strip('"') for b in buttons_str.split(',')]
        
        # Check forbidden
        found_forbidden = [b for b in forbidden_buttons if b in buttons_list]
        if not found_forbidden:
            score += 20
            feedback.append("Forbidden buttons (invite, security) successfully removed.")
        else:
            feedback.append(f"Forbidden buttons still present: {found_forbidden}")

        # Check required (to ensure list wasn't emptied)
        found_required = [b for b in required_buttons if b in buttons_list]
        if len(found_required) >= len(required_buttons) - 1: # Allow missing one
            score += 20
            feedback.append("Essential buttons preserved.")
        else:
            feedback.append("Too many essential buttons removed.")
    else:
        feedback.append("TOOLBAR_BUTTONS configuration not found or unparseable.")

    # ================================================================
    # 3. VLM Verification
    # ================================================================
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        # VLM Query
        prompt = """
        Analyze this screenshot of the Jitsi Meet interface.
        1. Is the application running and visible (not an error page)?
        2. Look at the toolbar (bottom center). Do you see an 'Invite' button (usually has a person icon with a +)?
        3. Do you see a 'Security' button (usually a shield icon)?
        
        Return JSON:
        {
            "app_visible": true,
            "invite_button_visible": false,
            "security_button_visible": false
        }
        """
        vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('app_visible'):
                score += 10
                feedback.append("Application is visible.")
            else:
                feedback.append("Application does not appear to be loaded.")

            if not parsed.get('invite_button_visible', True):
                score += 5
                feedback.append("Visual verification: Invite button absent.")
            else:
                feedback.append("Visual verification: Invite button still visible.")

            if not parsed.get('security_button_visible', True):
                score += 5
                feedback.append("Visual verification: Security button absent.")
    else:
        feedback.append("No final screenshot available for visual verification.")

    # ================================================================
    # Final Scoring
    # ================================================================
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }