#!/usr/bin/env python3
"""
Verifier for configure_domain_controller task.

Uses a Hybrid Verification Strategy:
1. File Verification: Checks if the agent created the result text file with correct details.
2. VLM Verification: Uses trajectory frames to verify the agent actually navigated the UI,
   filled the form, and attempted to save the domain controller configuration.
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Adjust path to find vlm_utils if needed, or define locally if strictly standalone
# Assuming gym_anything structure
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for standalone testing
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images): return {"success": False, "error": "VLM module not found"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_domain_controller(traj, env_info, task_info):
    """
    Verify that the domain controller was configured in ADAudit Plus.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_content_fragment = "corp.acmefinancial.com"
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------
    # 1. Retrieve Result JSON from Environment
    # ---------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        # Note: Container path is C:\workspace\task_result.json
        # But copy_from_env usually handles the mapping. 
        # If the environment is Windows, the path might need special handling depending on the backend.
        # Assuming the harness handles C:\ paths correctly or mapped volumes.
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ---------------------------------------------------
    # 2. Score File Evidence (40 Points)
    # ---------------------------------------------------
    output_exists = task_result.get('output_exists', False)
    file_created_during_task = task_result.get('file_created_during_task', False)
    content = task_result.get('output_content', "")
    
    if output_exists:
        score += 10
        feedback_parts.append("Result file created.")
        
        if file_created_during_task:
            score += 10
            feedback_parts.append("File timestamp valid.")
        else:
            feedback_parts.append("File timestamp invalid (pre-existed?).")
            
        if expected_content_fragment in content and "DC01" in content:
            score += 20
            feedback_parts.append("File content matches expected domain details.")
        else:
            feedback_parts.append(f"File content incorrect. Got: {content[:50]}...")
    else:
        feedback_parts.append("Result file NOT created.")

    # ---------------------------------------------------
    # 3. Score VLM Trajectory (60 Points)
    # ---------------------------------------------------
    # We need to verify the agent actually interacted with the UI, 
    # not just wrote the text file (anti-gaming).
    
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    if not frames and not final_screen:
        feedback_parts.append("No screenshots available for visual verification.")
    else:
        # Prepare VLM prompt
        all_images = frames + ([final_screen] if final_screen else [])
        
        prompt = """
        You are verifying an IT automation agent's work in ManageEngine ADAudit Plus.
        
        TASK: Add a Domain Controller.
        - Domain: corp.acmefinancial.com
        - DC: DC01.corp.acmefinancial.com
        
        Review the screenshots and answer:
        1. Did the agent navigate to the "Domain Settings" or "Configured Server" page?
        2. Did the agent fill in a form with "corp.acmefinancial.com" or "DC01"?
        3. Did the agent click Save/Add?
        4. Is the domain visible in the list (even if showing an error/red status)?
        
        Return JSON:
        {
            "navigated_to_settings": true/false,
            "entered_domain_details": true/false,
            "attempted_save": true/false,
            "domain_visible_in_list": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=all_images)
        
        if vlm_resp.get('success'):
            analysis = vlm_resp.get('parsed', {})
            
            if analysis.get('navigated_to_settings'):
                score += 15
                feedback_parts.append("VLM: Navigated to settings.")
            
            if analysis.get('entered_domain_details'):
                score += 15
                feedback_parts.append("VLM: Entered domain details.")
                
            if analysis.get('attempted_save'):
                score += 15
                feedback_parts.append("VLM: Attempted to save configuration.")
                
            if analysis.get('domain_visible_in_list'):
                score += 15
                feedback_parts.append("VLM: Domain entry visible in list.")
        else:
            feedback_parts.append("VLM verification failed to run.")

    # ---------------------------------------------------
    # 4. Final Assessment
    # ---------------------------------------------------
    # Pass threshold: 60 points
    # Must have at least some visual evidence or perfect file evidence
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }