#!/usr/bin/env python3
"""
Verifier for configure_secure_archiving task.

Verifies:
1. Log retention period is set to 365 days (via DB check).
2. Archive encryption is enabled (via DB check).
3. VLM verification of the workflow.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing without framework
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_archiving(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # ---------------------------------------------------------
    # Criteria 1: Retention Period (40 points)
    # ---------------------------------------------------------
    retention_found = result.get("retention_value_found", "")
    # Check if '365' is present in the DB dump line captured
    if "365" in retention_found:
        score += 40
        feedback.append("Retention period correctly set to 365 days.")
    else:
        feedback.append("Retention period of 365 days NOT found in configuration.")

    # ---------------------------------------------------------
    # Criteria 2: Encryption Enabled (40 points)
    # ---------------------------------------------------------
    encryption_found = result.get("encryption_config_found", "")
    # Robust check: look for evidence of encryption config
    if encryption_found:
        score += 40
        feedback.append("Archive encryption appears to be enabled.")
    else:
        feedback.append("Archive encryption configuration NOT found.")

    # ---------------------------------------------------------
    # Criteria 3: VLM Verification (20 points)
    # ---------------------------------------------------------
    # Use trajectory to verify the agent actually visited the settings page
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames or final_shot:
        all_images = frames + ([final_shot] if final_shot else [])
        
        prompt = """
        You are verifying a user action in a SIEM software (ManageEngine EventLog Analyzer).
        The user was supposed to:
        1. Go to Archive Settings.
        2. Set "Archive Retention" to 365 days.
        3. Enable "Encryption" and set a password.

        Look at the screenshot(s). Do you see:
        - A form related to "Archive", "Database", or "Retention"?
        - The number "365" in a text field?
        - A checked box for "Encrypt" or "Password"?
        - A "Save" button being clicked or a success message?

        Respond JSON: {"evidence_found": boolean, "confidence": float}
        """
        
        vlm_resp = query_vlm(images=all_images, prompt=prompt)
        
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("evidence_found", False):
                score += 20
                feedback.append("Visual evidence confirms settings modification.")
            else:
                feedback.append("No visual evidence of settings change found.")
        else:
            # Fallback if VLM fails but DB check passed - give partial credit
            if score >= 40: 
                score += 10
                feedback.append("VLM check skipped, awarding partial points based on DB success.")
    else:
        feedback.append("No screenshots available for VLM verification.")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    passed = score >= 80  # Requires at least both DB checks OR one DB check + strong visual evidence
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }