#!/usr/bin/env python3
"""
Verifier for configure_python_cgi task.
Verifies that Python scripts execute as CGI on the target virtual server.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_python_cgi(traj, env_info, task_info):
    """
    Verify the task based on functional tests performed in export_result.sh
    and visual evidence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load scoring weights
    metadata = task_info.get('metadata', {})
    scoring = metadata.get('scoring', {
        "execution_success": 40,
        "source_hidden": 20,
        "http_ok": 10,
        "config_updated": 20,
        "site_stability": 10
    })

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Functional Execution Check (Primary)
    execution_success = result.get("execution_success", False)
    source_visible = result.get("source_visible", False)
    http_status = int(result.get("http_status", 0))

    if execution_success:
        score += scoring["execution_success"]
        feedback_parts.append("Python script executed successfully")
    else:
        feedback_parts.append("Python script execution failed")

    # 2. Source Code Hidden Check
    # If execution failed, source might be visible. If execution worked, source is hidden.
    if not source_visible:
        score += scoring["source_hidden"]
        feedback_parts.append("Source code is hidden")
    else:
        feedback_parts.append("Source code was displayed (security risk)")

    # 3. HTTP Status Check
    if http_status == 200:
        score += scoring["http_ok"]
        feedback_parts.append("HTTP 200 OK received")
    else:
        feedback_parts.append(f"Received HTTP {http_status}")

    # 4. Configuration Check
    if result.get("config_updated", False):
        score += scoring["config_updated"]
        feedback_parts.append("Apache configuration updated")
    else:
        feedback_parts.append("Apache configuration not validated")

    # 5. Stability Check
    if result.get("site_stable", False):
        score += scoring["site_stability"]
        feedback_parts.append("Main site remains accessible")
    else:
        feedback_parts.append("Main site is down")

    # 6. VLM Trajectory Verification (Supplementary)
    # Ensure they actually used the UI and didn't just hack a config file via terminal (if terminal was available)
    # The prompt checks if they interacted with the website options/configuration pages.
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Review these screenshots of a Virtualmin administration session. "
            "Did the user access the 'Website Options', 'Apache Configuration', or 'CGI' settings "
            "for a virtual server? Look for checkboxes regarding 'CGI' or file extensions like '.py'."
        )
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_result and vlm_result.get("success"):
                logger.info(f"VLM Verification: {vlm_result.get('answer')}")
                # We don't strictly penalize here if functional tests pass, 
                # but we could use this to flag manual file edits vs UI usage.
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final logic
    passed = execution_success and not source_visible and http_status == 200
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }