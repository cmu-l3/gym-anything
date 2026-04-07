#!/usr/bin/env python3
"""
Verifier for configure_powershell_auditing task.

Verifies that:
1. The user navigated to the PowerShell auditing section.
2. The domain 'corp.acmefinancial.com' was configured.
3. 'Script Block Logging' was enabled.
4. The configuration was saved.

Uses a hybrid approach:
- Checks programmatic signals (DB query results from export_result.ps1)
- Uses VLM to verify UI interactions and final state from screenshots/trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_powershell_auditing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification
    # We check the trajectory to confirm the workflow was followed
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    prompt = """
    You are verifying an IT configuration task in ManageEngine ADAudit Plus.
    
    **Goal:** Configure PowerShell Auditing for domain 'corp.acmefinancial.com' and enable 'Script Block Logging'.
    
    Review the screenshots and determine:
    1. Did the user navigate to the **PowerShell Auditing** or **Server Audit** configuration page?
    2. Is the domain name `corp.acmefinancial.com` visible in any input field or list?
    3. Is the **Script Block Logging** checkbox/toggle CHECKED or ENABLED?
    4. Did the user click 'Save' or is the configuration visible in a 'Configured Domains' list at the end?
    
    Note: Connection errors (red text saying 'Network path not found') are ACCEPTABLE and expected. The key is that the user entered the details and attempted to save/add the config.
    
    Respond in JSON:
    {
        "navigated_to_powershell_config": true/false,
        "domain_entered": true/false,
        "script_block_logging_enabled": true/false,
        "save_attempted_or_completed": true/false,
        "confidence": "low/medium/high",
        "reasoning": "..."
    }
    """
    
    # Use final screenshot + frames for context
    vlm_images = frames + ([final_shot] if final_shot else [])
    
    vlm_result = query_vlm(images=vlm_images, prompt=prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Navigation (20 pts)
    if vlm_data.get("navigated_to_powershell_config"):
        score += 20
        feedback.append("Correctly navigated to PowerShell configuration.")
    else:
        feedback.append("Failed to find PowerShell configuration section.")

    # Criterion 2: Domain Entry (20 pts)
    # Check DB signal OR VLM signal
    if result_data.get("domain_found_in_db") or vlm_data.get("domain_entered"):
        score += 20
        feedback.append("Target domain 'corp.acmefinancial.com' entered correctly.")
    else:
        feedback.append("Target domain not found in configuration.")

    # Criterion 3: Script Block Logging (30 pts) - CRITICAL
    # This is the security feature requested
    if result_data.get("script_block_enabled_in_db") or vlm_data.get("script_block_logging_enabled"):
        score += 30
        feedback.append("Script Block Logging enabled.")
    else:
        feedback.append("CRITICAL: Script Block Logging was NOT enabled.")

    # Criterion 4: Save/Completion (30 pts)
    if vlm_data.get("save_attempted_or_completed"):
        score += 30
        feedback.append("Configuration saved successfully.")
    else:
        feedback.append("Configuration was not saved.")

    # Pass Threshold
    passed = score >= 70
    
    # Anti-gaming check: Ensure task didn't finish instantly (timestamps)
    task_duration = result_data.get("task_end", 0) - result_data.get("task_start", 0)
    if task_duration < 10:
        passed = False
        score = 0
        feedback = ["Task completed too quickly (anti-gaming)."]

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }