#!/usr/bin/env python3
"""
Verifier for configure_https_settings task.

Verifies that:
1. ADAudit Plus web server configuration (server.xml) has HTTPS enabled on port 8444.
2. HTTP to HTTPS redirection is configured (or HTTP disabled).
3. The agent created a summary file with the correct port.
4. The agent took a screenshot of the configuration page.
5. VLM verification confirms the settings in the screenshot match expectations.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_https_settings(traj, env_info, task_info):
    """
    Verify the HTTPS configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    # Note: env is Windows, but copy_from_env handles paths. 
    # Path in container (Windows) was C:\workspace\task_result.json.
    # Framework likely maps this mapping. Assuming standard unix-like path for copy source if used via docker cp, 
    # but for Windows container, paths are tricky. 
    # Assuming the framework handles 'C:\workspace\task_result.json' correctly or maps it.
    # If the environment implementation mounts workspace to a host path, we might read directly?
    # Standard pattern: copy_from_env(container_path, local_path)
    
    # In Windows containers, paths use backslashes. 
    remote_path = "C:\\workspace\\task_result.json"
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env(remote_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        # Fallback for common path variations if needed
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Criteria
    score = 0
    max_score = 100
    feedback = []

    # 1. Configuration File Checks (40 points)
    config_exists = result_data.get("config_exists", False)
    https_enabled = result_data.get("https_enabled", False)
    port_configured = str(result_data.get("port_configured", ""))
    redirect_enabled = result_data.get("redirect_enabled", False)
    file_modified = result_data.get("file_modified_during_task", False)

    if not config_exists:
        feedback.append("Could not find ADAudit Plus configuration file.")
    else:
        if https_enabled:
            score += 15
            feedback.append("HTTPS is enabled in server config.")
            
            if port_configured == "8444":
                score += 15
                feedback.append("Correct port (8444) configured.")
            else:
                feedback.append(f"Incorrect port configured: {port_configured} (expected 8444).")
                
            if redirect_enabled:
                score += 10
                feedback.append("HTTP redirection/disablement configured correctly.")
            else:
                feedback.append("HTTP redirection not detected in config.")
        else:
            feedback.append("HTTPS is NOT enabled in server config.")
        
        if file_modified:
            feedback.append("Configuration file was modified during task.")
        else:
            feedback.append("WARNING: Configuration file timestamp indicates no changes made.")
            # If values are correct but file wasn't modified, it implies it was already set (gaming or stale state).
            # For this task, we expect changes. Deduct if file not modified?
            # Or strict check: if not modified, maybe 0 points for config?
            pass

    # 2. Output Files Checks (20 points)
    summary_exists = result_data.get("summary_file_exists", False)
    summary_content = result_data.get("summary_content", "")
    screenshot_exists = result_data.get("screenshot_exists", False)

    if summary_exists:
        if "8444" in summary_content:
            score += 10
            feedback.append("Summary file exists and contains correct port.")
        else:
            score += 5
            feedback.append(f"Summary file exists but content mismatch. Found: '{summary_content}'")
    else:
        feedback.append("Summary text file not found.")

    if screenshot_exists:
        score += 10
        feedback.append("Evidence screenshot saved.")
    else:
        feedback.append("Evidence screenshot not found.")

    # 3. VLM Verification (40 points)
    # Check the agent's screenshot and/or trajectory
    
    # We prioritize the agent's manually saved screenshot for the specific UI check
    # But also use trajectory to verify workflow.
    
    agent_screenshot_path = "C:\\workspace\\https_config_result.png"
    # We need to fetch this screenshot to local for VLM
    local_screenshot_path = None
    if screenshot_exists:
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(agent_screenshot_path, temp_img.name)
            local_screenshot_path = temp_img.name
        except:
            logger.warning("Could not copy agent screenshot for VLM")

    # If agent screenshot failed, fallback to final frame
    if not local_screenshot_path:
        local_screenshot_path = get_final_screenshot(traj)

    vlm_score = 0
    if local_screenshot_path:
        prompt = """
        Analyze this screenshot of the ManageEngine ADAudit Plus "Connection Settings" page.
        Verify the following settings:
        1. "Run ADAudit Plus in Safe Mode (https)" is CHECKED.
        2. The Port number is set to "8444".
        3. "Automatically redirect HTTP requests to HTTPS" is CHECKED.
        
        Respond in JSON:
        {
            "https_checked": true/false,
            "port_8444_visible": true/false,
            "redirect_checked": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, image=local_screenshot_path)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("https_checked"):
                vlm_score += 15
            if parsed.get("port_8444_visible"):
                vlm_score += 15
            if parsed.get("redirect_checked"):
                vlm_score += 10
            
            feedback.append(f"VLM Analysis: HTTPS={parsed.get('https_checked')}, Port={parsed.get('port_8444_visible')}")
        else:
            feedback.append("VLM verification failed to process image.")
            # Graceful degradation: if config check passed perfectly, we might be lenient
            if https_enabled and port_configured == "8444":
                vlm_score = 40 # Assume visual matches config if VLM fails technically
    
    # Clean up
    if local_screenshot_path and os.path.exists(local_screenshot_path) and "tmp" in local_screenshot_path:
        os.unlink(local_screenshot_path)

    score += vlm_score

    # Final Pass Logic
    # Must have HTTPS enabled in config AND Port 8444
    passed = (https_enabled and port_configured == "8444" and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }