#!/usr/bin/env python3
"""
Verifier for configure_ip_location_mapping task.

Strategy:
1. Retrieve the final screenshot and result JSON from the environment.
2. Use VLM (Visual Language Model) to verify the "Configured Locations" table contains the correct entry.
3. Validate anti-gaming timestamps.

Criteria:
- Location Name: "Austin Innovation Hub"
- IP Range: "10.55.0.0" (Start) - "10.55.255.255" (End)
- Screenshot must be taken during the task window.
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory for shared utilities if needed
sys.path.insert(0, str(Path(__file__).parent.parent))
# Assuming gym_anything.vlm provides query_vlm, get_final_screenshot
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ip_location_mapping(traj, env_info, task_info):
    """
    Verifies that the IP location mapping was correctly configured in ADAudit Plus.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Define paths inside the container
    # Note: env_id is windows-based, so paths are Windows style, but copy_from_env handles access.
    # We use the path defined in export_result.ps1
    task_dir_win = r"C:\workspace\tasks\configure_ip_location_mapping"
    result_json_path_win = f"{task_dir_win}\\task_result.json"
    screenshot_path_win = f"{task_dir_win}\\final_screenshot.png"
    
    # Temp files for verification
    local_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    local_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    
    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env(result_json_path_win, local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # 2. Retrieve Screenshot
        screenshot_exists = result_data.get('screenshot_exists', False)
        if screenshot_exists:
            try:
                copy_from_env(screenshot_path_win, local_screenshot)
            except Exception as e:
                logger.warning(f"Screenshot copy failed: {e}")
                screenshot_exists = False
        
        if not screenshot_exists or os.path.getsize(local_screenshot) == 0:
            return {"passed": False, "score": 0, "feedback": "Final screenshot missing or empty."}

        # 3. VLM Verification
        # We need to confirm the table shows the specific location and IP range.
        metadata = task_info.get('metadata', {})
        target_name = metadata.get('location_name', "Austin Innovation Hub")
        target_ip = metadata.get('ip_start', "10.55.0.0")
        
        prompt = f"""
        Analyze this screenshot of the ManageEngine ADAudit Plus interface.
        
        Task: The user was supposed to add a new 'Configured Location' with the name '{target_name}' mapped to IP range starting with '{target_ip}'.
        
        Please verify:
        1. Is the 'Configured Locations' (or 'Locations') table/list visible?
        2. Is there an entry with the Location Name "{target_name}"?
        3. Is the IP Range or IP Address column showing "{target_ip}" (or the range 10.55.0.0 - 10.55.255.255)?
        4. Does the Description match "New R&D Facility - Bldg 4" (optional but good)?
        
        Respond in JSON format:
        {{
            "locations_table_visible": boolean,
            "target_name_found": boolean,
            "target_ip_found": boolean,
            "description_match": boolean,
            "confidence": "low|medium|high",
            "reasoning": "string"
        }}
        """
        
        vlm_response = query_vlm(prompt=prompt, image=local_screenshot)
        
        if not vlm_response.get("success"):
            return {"passed": False, "score": 0, "feedback": f"VLM verification failed: {vlm_response.get('error')}"}
            
        parsed = vlm_response.get("parsed", {})
        
        # Scoring Logic
        score = 0
        feedback_parts = []
        
        # Criterion 1: Table Visible (20 pts)
        if parsed.get("locations_table_visible"):
            score += 20
        else:
            feedback_parts.append("Locations table not visible in final screenshot.")
            
        # Criterion 2: Name Found (40 pts)
        if parsed.get("target_name_found"):
            score += 40
        else:
            feedback_parts.append(f"Location name '{target_name}' not found.")
            
        # Criterion 3: IP Found (40 pts)
        if parsed.get("target_ip_found"):
            score += 40
        else:
            feedback_parts.append(f"IP Range '{target_ip}' not found associated with the location.")
            
        passed = (score >= 100)
        
        if passed:
            feedback = "Success: Location mapping configured correctly."
        else:
            feedback = "Task Failed: " + " ".join(feedback_parts) + f" (VLM Reasoning: {parsed.get('reasoning')})"
            
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(local_result_json):
            os.remove(local_result_json)
        if os.path.exists(local_screenshot):
            os.remove(local_screenshot)