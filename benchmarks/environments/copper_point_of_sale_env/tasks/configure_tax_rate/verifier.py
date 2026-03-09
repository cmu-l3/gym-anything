#!/usr/bin/env python3
"""
Verifier for configure_tax_rate task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_tax_rate(traj, env_info, task_info):
    """
    Verify that the sales tax was configured correctly.
    
    Combines file-based verification (checking internal config files)
    with VLM verification of the UI state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load File-based Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    config_modified = result.get("config_modified", False)
    tax_name_found = result.get("tax_name_found", False)
    tax_rate_found = result.get("tax_rate_found", False)
    app_running = result.get("app_running", False)

    score = 0
    feedback = []

    # Scoring - File Evidence (60 points)
    if config_modified:
        score += 10
        feedback.append("Configuration files were modified.")
    else:
        feedback.append("No configuration changes detected in file system.")

    if tax_name_found:
        score += 25
        feedback.append("Tax name 'TX Sales Tax' found in config.")
    else:
        feedback.append("Tax name 'TX Sales Tax' NOT found in config files.")

    if tax_rate_found:
        score += 25
        feedback.append("Tax rate '8.25' found in config.")
    else:
        feedback.append("Tax rate '8.25' NOT found in config files.")

    # Scoring - VLM Evidence (40 points)
    # Check trajectory for settings screen and correct values
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of NCH Copper Point of Sale.
    The user is supposed to configure a sales tax.
    
    Look for:
    1. The 'Options' or 'Settings' window.
    2. A 'Tax' tab or section.
    3. An entry in the list or a form with:
       - Name: "TX Sales Tax"
       - Rate/Percentage: "8.25" or "8.25%"
       
    Does the final state or the trajectory show that this tax was successfully added?
    Reply with JSON: {"success": bool, "confidence": float, "reason": str}
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    vlm_success = False
    if vlm_result and isinstance(vlm_result, dict):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("success", False):
            vlm_success = True
            score += 40
            feedback.append("VLM verified tax configuration in UI.")
        else:
            feedback.append(f"VLM did not verify success: {parsed.get('reason', 'Unknown')}")
    else:
        # Fallback if VLM fails technically
        feedback.append("VLM verification unavailable.")

    # Final Pass Logic
    # Must have at least name found OR (VLM success AND file modified)
    # We require some file evidence to prevent pure UI gaming, 
    # but VLM can save the day if file parsing misses binary formats.
    
    passed = False
    if score >= 75:  # High bar
        passed = True
    elif score >= 60 and tax_name_found and tax_rate_found:
        passed = True
    elif score >= 50 and vlm_success and config_modified:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }