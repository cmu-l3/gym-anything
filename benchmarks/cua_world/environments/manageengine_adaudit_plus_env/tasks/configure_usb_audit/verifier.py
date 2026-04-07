#!/usr/bin/env python3
"""
Verifier for configure_usb_audit task in ManageEngine ADAudit Plus.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_usb_audit(traj, env_info, task_info):
    """
    Verify that USB/Peripheral auditing was configured correctly.
    
    Strategy:
    1. File-based: Check if the agent saved the requested screenshot and summary file.
    2. VLM-based: 
       - Check trajectory to ensure agent navigated to configuration pages.
       - Check the agent's output screenshot for enabled settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Results (JSON from export script)
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        # Path inside container is C:\workspace\task_result.json
        # The copy_from_env usually handles the path mapping from the guest
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution results."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ------------------------------------------------------------------
    # 2. File-based Verification (40 points)
    # ------------------------------------------------------------------
    # Check Screenshot File
    if task_result.get("output_image_exists") and task_result.get("output_image_created_during_task"):
        if task_result.get("output_image_size", 0) > 10240: # > 10KB
            score += 20
            feedback_parts.append("Evidence screenshot created.")
        else:
            feedback_parts.append("Evidence screenshot too small/empty.")
    else:
        feedback_parts.append("Evidence screenshot missing or not created during task.")

    # Check Summary File
    if task_result.get("output_summary_exists") and task_result.get("output_summary_created_during_task"):
        score += 20
        feedback_parts.append("Summary file created.")
    else:
        feedback_parts.append("Summary file missing.")

    # ------------------------------------------------------------------
    # 3. VLM Verification of Agent's Output Screenshot (30 points)
    # ------------------------------------------------------------------
    # We need to analyze the screenshot the AGENT saved: C:\workspace\usb_audit_config_result.png
    # We need to copy it out first
    agent_screenshot_score = 0
    if task_result.get("output_image_exists"):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("C:\\workspace\\usb_audit_config_result.png", temp_img.name)
            
            prompt = """
            Examine this screenshot of ManageEngine ADAudit Plus configuration.
            Does it show "Removable Storage Auditing" or "USB Audit" settings?
            Are the checkboxes for "USB Storage Device Connected" or similar enabled/checked?
            Is the configuration saved or applied?
            
            Return JSON:
            {
                "is_audit_config_page": true/false,
                "usb_audit_enabled": true/false,
                "event_types_checked": true/false
            }
            """
            vlm_res = query_vlm(images=[temp_img.name], prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('is_audit_config_page'):
                agent_screenshot_score += 10
            if parsed.get('usb_audit_enabled'):
                agent_screenshot_score += 10
            if parsed.get('event_types_checked'):
                agent_screenshot_score += 10
                
            score += agent_screenshot_score
            feedback_parts.append(f"Agent screenshot analysis score: {agent_screenshot_score}/30")
            
        except Exception as e:
            feedback_parts.append(f"Failed to verify agent screenshot: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    
    # ------------------------------------------------------------------
    # 4. VLM Verification of Trajectory (30 points)
    # ------------------------------------------------------------------
    # Check if agent actually navigated through the UI
    frames = sample_trajectory_frames(traj, n=5)
    final_shot = get_final_screenshot(traj)
    
    traj_prompt = """
    Review this sequence of screenshots from an agent using ADAudit Plus.
    Did the agent navigate to the 'Configuration' or 'Admin' section?
    Did the agent access 'File Audit' or 'Server Audit' settings?
    Did the agent reach a page related to 'Removable Storage' or 'USB'?
    
    Return JSON:
    {
        "navigated_to_config": true/false,
        "accessed_usb_settings": true/false,
        "workflow_completed": true/false
    }
    """
    
    # Include final shot in analysis
    images_to_check = frames
    if final_shot:
        images_to_check.append(final_shot)
        
    if images_to_check:
        vlm_traj_res = query_vlm(images=images_to_check, prompt=traj_prompt)
        parsed_traj = vlm_traj_res.get('parsed', {})
        
        traj_score = 0
        if parsed_traj.get('navigated_to_config'):
            traj_score += 10
        if parsed_traj.get('accessed_usb_settings'):
            traj_score += 10
        if parsed_traj.get('workflow_completed'):
            traj_score += 10
            
        score += traj_score
        feedback_parts.append(f"Trajectory analysis score: {traj_score}/30")
    else:
        feedback_parts.append("No trajectory frames available for verification.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }