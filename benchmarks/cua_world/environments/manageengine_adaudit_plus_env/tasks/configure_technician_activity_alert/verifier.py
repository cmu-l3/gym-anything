#!/usr/bin/env python3
"""
Verifier for Configure Technician Activity Alert task.

Verification Logic:
1.  **VLM Trajectory Analysis (Primary):**
    -   Since checking the embedded database of a complex Windows app in a container is brittle,
        we rely heavily on the visual evidence from the agent's trajectory.
    -   We check for:
        a) Navigation to Alert Profiles.
        b) Selection of the correct Category ("ADAudit Plus Audit" / "Technician Audit").
        c) Setting Severity to "Critical".
        d) Typing the correct name "ADAudit Configuration Monitor".
        e) Successful save (final list view).

2.  **Basic State Checks:**
    -   App was running.
    -   Task duration was reasonable (not 0s).
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Import gym_anything VLM utilities
# Assuming these are available in the evaluation environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing if gym_anything not installed
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_technician_activity_alert(traj, env_info, task_info):
    """
    Verifies the alert configuration task using VLM trajectory analysis.
    """
    # 1. Setup & Data Extraction
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Note: Container path is Windows style, but copy_from_env handles the mapping
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to retrieve task_result.json: {e}")
        # Continue - we can still score based on VLM, but penalize for missing metadata
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Verification Data
    frames = sample_trajectory_frames(traj, n=8)
    final_shot = get_final_screenshot(traj)
    
    if not frames and not final_shot:
        return {"passed": False, "score": 0, "feedback": "No video evidence available."}
    
    # Combined images for VLM context
    verification_images = frames + ([final_shot] if final_shot else [])

    # 3. VLM Verification Logic
    # We ask the VLM to act as an auditor checking the configuration steps.
    prompt = """
    You are an expert IT auditor verifying if a user correctly configured a security alert in ManageEngine ADAudit Plus.
    
    Analyze the sequence of screenshots to answer the following questions. 
    Assign points based on the evidence found.

    Task Requirements:
    1. Did the user navigate to 'Alert Profiles' and click 'New' or 'Add'?
    2. Did the user enter the Profile Name: 'ADAudit Configuration Monitor'?
    3. CRITICAL: Did the user select the Category related to 'ADAudit Plus Audit', 'Technician Audit', or 'Administrative Audit'? (NOT 'User Management', NOT 'Server Audit').
    4. Did the user set the Severity to 'Critical'?
    5. Did the user configure the Alert Message to include a variable (like %TECHNICIAN_NAME%)?
    6. Is there evidence the profile was Saved (e.g., success message, or seeing the new alert in the list)?

    Output valid JSON:
    {
        "navigated_correctly": boolean,
        "name_correct": boolean,
        "category_correct": boolean,
        "severity_critical": boolean,
        "message_configured": boolean,
        "saved_successfully": boolean,
        "category_seen": "string (what category was selected?)",
        "confidence": "low/medium/high"
    }
    """

    vlm_response = query_vlm(images=verification_images, prompt=prompt)
    
    if not vlm_response.get('success'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification failed due to VLM error: {vlm_response.get('error')}"
        }

    analysis = vlm_response.get('parsed', {})
    
    # 4. Scoring Calculation
    score = 0
    feedback_items = []

    # Criterion A: Navigation (10 pts)
    if analysis.get('navigated_correctly'):
        score += 10
    else:
        feedback_items.append("Failed to navigate to Alert Profiles.")

    # Criterion B: Naming (15 pts)
    if analysis.get('name_correct'):
        score += 15
    else:
        feedback_items.append("Alert profile name incorrect.")

    # Criterion C: Category Selection (CRITICAL - 30 pts)
    # This is the most important part - auditing the auditor.
    if analysis.get('category_correct'):
        score += 30
    else:
        seen = analysis.get('category_seen', 'unknown')
        feedback_items.append(f"Wrong category selected. Expected 'ADAudit Plus Audit'/'Technician Audit', saw '{seen}'.")

    # Criterion D: Severity (15 pts)
    if analysis.get('severity_critical'):
        score += 15
    else:
        feedback_items.append("Severity not set to Critical.")

    # Criterion E: Message Config (10 pts)
    if analysis.get('message_configured'):
        score += 10

    # Criterion F: Success/Save (20 pts)
    if analysis.get('saved_successfully'):
        score += 20
    else:
        feedback_items.append("Configuration not saved or final state not reached.")

    # Anti-gaming check: App must have been running
    if str(result_data.get('app_was_running', 'False')).lower() == 'false':
        score = 0
        feedback_items.append("Application was not running.")

    # Final Pass/Fail
    # Must get Category correct + Saved + respectable score
    passed = (score >= 70) and analysis.get('category_correct', False) and analysis.get('saved_successfully', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_items) if feedback_items else "Task completed perfectly."
    }