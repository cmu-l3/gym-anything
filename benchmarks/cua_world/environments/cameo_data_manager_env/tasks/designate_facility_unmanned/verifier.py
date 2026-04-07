#!/usr/bin/env python3
"""
Verifier for designate_facility_unmanned task.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_designate_facility_unmanned(traj, env_info, task_info):
    """
    Verify that the facility was correctly designated as unmanned.
    
    Criteria:
    1. Database: Facility 'North Creek Lift Station' exists.
    2. Database: 'Manned' field is False/0 (Unchecked).
    3. Database: 'LocationOfPlans' contains 'Public Works HQ'.
    4. Anti-gaming: Database file was modified during task.
    5. VLM: Visual confirmation of the checkbox and text field.
    """
    
    # Setup helpers
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    # Retrieve metadata expectations
    metadata = task_info.get('metadata', {})
    expected_location_fragment = "Public Works HQ"
    
    # 1. Retrieve JSON result from guest
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The guest path is Windows format, but copy_from_env handles the abstraction usually.
        # However, standard practice in these envs is to copy from the path written by export script.
        # Windows paths in copy_from_env might need careful handling. 
        # Assuming the env mapping mounts C:\tmp to /tmp or handles paths correctly.
        # If not, we try standard unix-like path valid in win-containers (C:/tmp/...)
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to copy/read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Programmatic Scoring
    score = 0
    feedback = []
    
    # Check if facility was found in DB
    if not result_data.get('facility_found', False):
        return {"passed": False, "score": 0, "feedback": "Facility 'North Creek Lift Station' not found in database."}
    
    score += 10
    feedback.append("Facility found in database.")
    
    # Check Manned Status (Should be False)
    # result_data['manned_status'] is boolean from PS script
    manned = result_data.get('manned_status', True)
    if manned is False:
        score += 30
        feedback.append("Success: 'Manned' status is unchecked.")
    else:
        feedback.append("Fail: 'Manned' status is still checked (True).")
        
    # Check Plan Location Text
    location_text = result_data.get('location_of_plans', "")
    if expected_location_fragment.lower() in location_text.lower():
        score += 30
        feedback.append(f"Success: Plan location updated to '{location_text}'.")
    else:
        feedback.append(f"Fail: Plan location text incorrect. Found: '{location_text}'.")
        
    # Check Activity (Anti-gaming)
    if result_data.get('db_modified_during_task', False):
        score += 10
        feedback.append("Database modification detected.")
    else:
        feedback.append("Warning: No database modification timestamp change detected.")
        
    # 3. VLM Verification
    # Use the final screenshot from the trajectory
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Review this screenshot of CAMEO Data Manager.
        The user should have:
        1. Unchecked the "Manned" checkbox.
        2. Entered "Public Works HQ" in the "Location of Plans" (or Plan Location) field.
        
        Return JSON:
        {
            "manned_unchecked": boolean,
            "location_text_visible": boolean,
            "location_text_content": string
        }
        """
        try:
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_response.get('parsed', {})
            
            if parsed.get('manned_unchecked', False):
                vlm_score += 10
                feedback.append("VLM confirms 'Manned' unchecked.")
                
            if parsed.get('location_text_visible', False):
                content = parsed.get('location_text_content', '').lower()
                if 'public' in content or 'works' in content:
                    vlm_score += 10
                    feedback.append("VLM confirms location text visible.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score
    
    # Calculate Pass
    # Passing requires Manned=False AND Location correct
    passed = (manned is False) and (expected_location_fragment.lower() in location_text.lower())
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }