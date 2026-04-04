#!/usr/bin/env python3
"""
Verifier for enforce_identity_validation task.

Criteria:
1. Config File (40 pts):
   - custom-config.js exists
   - Contains prejoinPageEnabled = true
   - Contains requireDisplayName = true
2. Evidence Screenshots (50 pts):
   - evidence_blocked.png: VLM confirms pre-join screen with validation error/disabled join.
   - evidence_success.png: VLM confirms active meeting.
3. Process (10 pts):
   - Config modified during task.
   - Jitsi is running at the end.
"""

import json
import base64
import os
import tempfile
import logging

# Import VLM utilities from framework
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identity_validation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- Criterion 1: Configuration (40 pts) ---
    config_exists = result.get("config_exists", False)
    config_b64 = result.get("config_content_b64", "")
    
    if config_exists and config_b64:
        try:
            config_content = base64.b64decode(config_b64).decode('utf-8')
            
            # Check for key parameters
            has_prejoin = "prejoinPageEnabled" in config_content and "true" in config_content.split("prejoinPageEnabled")[1].split("\n")[0].lower()
            has_require_name = "requireDisplayName" in config_content and "true" in config_content.split("requireDisplayName")[1].split("\n")[0].lower()
            
            # More robust checking can be done with regex if needed, but simple string check usually suffices for JS config files
            # checks if "prejoinPageEnabled: true" or "prejoinPageEnabled = true" roughly exists
            
            if has_prejoin:
                score += 20
                feedback_parts.append("Pre-join enabled in config.")
            else:
                feedback_parts.append("Pre-join NOT enabled in config.")
                
            if has_require_name:
                score += 20
                feedback_parts.append("Display name requirement enabled.")
            else:
                feedback_parts.append("Display name requirement NOT enabled.")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing config: {e}")
    else:
        feedback_parts.append("Config file not found.")

    # --- Criterion 2: VLM Evidence Analysis (50 pts) ---
    blocked_path = result.get("blocked_evidence_path")
    success_path = result.get("success_evidence_path")
    
    # Verify Blocked Screenshot
    if result.get("blocked_evidence_exists"):
        local_blocked = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(blocked_path, local_blocked)
            vlm_res = query_vlm(
                prompt="Is this a video conferencing pre-join screen? Is the 'Join' button disabled, grayed out, or is there an error message saying a name is required?",
                image=local_blocked
            )
            
            if vlm_res.get("success") and (
                "disabled" in vlm_res.get("parsed", {}).get("answer", "").lower() or 
                "gray" in vlm_res.get("parsed", {}).get("answer", "").lower() or
                "error" in vlm_res.get("parsed", {}).get("answer", "").lower() or
                "required" in vlm_res.get("parsed", {}).get("answer", "").lower()
            ):
                score += 25
                feedback_parts.append("Verified blocked state evidence.")
            else:
                feedback_parts.append("Blocked evidence screenshot did not pass VLM check.")
        except Exception as e:
            feedback_parts.append(f"Failed to verify blocked evidence: {e}")
        finally:
            if os.path.exists(local_blocked):
                os.unlink(local_blocked)
    else:
        feedback_parts.append("Blocked evidence screenshot missing.")

    # Verify Success Screenshot
    if result.get("success_evidence_exists"):
        local_success = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(success_path, local_success)
            vlm_res = query_vlm(
                prompt="Is this an active video meeting? Can you see a toolbar at the bottom or a video grid?",
                image=local_success
            )
            
            if vlm_res.get("success") and "yes" in vlm_res.get("parsed", {}).get("answer", "").lower():
                score += 25
                feedback_parts.append("Verified success state evidence.")
            else:
                feedback_parts.append("Success evidence screenshot did not pass VLM check.")
        except Exception as e:
            feedback_parts.append(f"Failed to verify success evidence: {e}")
        finally:
            if os.path.exists(local_success):
                os.unlink(local_success)
    else:
        feedback_parts.append("Success evidence screenshot missing.")

    # --- Criterion 3: Process & State (10 pts) ---
    if result.get("config_modified_during_task"):
        score += 5
    if result.get("jitsi_running"):
        score += 5

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }