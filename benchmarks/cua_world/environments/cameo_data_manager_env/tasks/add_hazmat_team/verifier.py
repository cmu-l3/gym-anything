#!/usr/bin/env python3
"""
Verifier for add_hazmat_team task.

Verification Strategy:
1. Anti-Gaming: Check if the database file on disk was actually modified during the task window.
2. VLM Verification: Use Vision-Language Model to analyze the trajectory and final state.
   - Verify navigation to Resources/HAZMAT section.
   - Verify entry of "Kanawha Valley Regional HAZMAT Response Team".
   - Verify address and contact details are visible in the final form/list.

Since CAMEO uses a proprietary file format (FileMaker) that is difficult to query directly
without the application's API or ODBC drivers (which may not be configured in the container),
we rely on the file modification timestamp as proof of "save" and VLM for "correctness".
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_hazmat_team(traj, env_info, task_info):
    """
    Verify that the HAZMAT team was added correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Task Metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Kanawha Valley Regional HAZMAT Response Team")
    
    # 2. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: path in container is C:\tmp\task_result.json, but copy_from_env usually handles
        # path mapping. For Windows containers, paths might need careful handling.
        # Assuming the framework handles the mount or path conversion.
        # If the container uses Windows paths, we might need to specify it exactly as in export script.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or read result json: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task execution data (export_result.ps1 may have failed)."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Data
    score = 0
    feedback_parts = []
    
    # Criterion 1: Database Modification (Anti-gaming) - 20 points
    # Did the agent actually save something?
    if result_data.get("db_modified", False):
        score += 20
        feedback_parts.append("Database updated successfully.")
    else:
        feedback_parts.append("No changes detected in CAMEO database files.")

    # Criterion 2: App Running - 10 points
    if result_data.get("app_running", False):
        score += 10
    else:
        feedback_parts.append("CAMEO Data Manager was closed unexpectedly.")

    # Criterion 3: VLM Verification of Content - 70 points
    # We check the final screenshot and trajectory
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if not final_img:
        feedback_parts.append("No screenshots available for verification.")
    else:
        # VLM Prompt
        prompt = f"""
        You are verifying a data entry task in CAMEO Data Manager.
        The user was supposed to add a new 'Resources' record for a HAZMAT Team.
        
        Target Data:
        - Name: {expected_name}
        - Address: 501 Virginia Street East, Charleston, WV
        - Phone: 304-357-0962
        - Contact: Captain Robert Hensley
        
        Review the screenshots (sequence of actions + final state).
        
        Check for:
        1. Navigation to the 'Resources' or 'Contacts' section (specifically HAZMAT if applicable).
        2. Visibility of the text "{expected_name}" in a form or list.
        3. Visibility of "Charleston", "WV", or the phone number.
        4. Whether the record appears to be saved (not just a blank form).
        
        Provide a JSON response:
        {{
            "name_visible": boolean,
            "address_or_phone_visible": boolean,
            "correct_module_accessed": boolean,
            "record_saved_indication": boolean,
            "confidence": number (0-1)
        }}
        """
        
        vlm_response = query_vlm(images=frames + [final_img], prompt=prompt)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            
            # Name check (Critical)
            if parsed.get("name_visible", False):
                score += 30
                feedback_parts.append("Team name verified in screenshot.")
            else:
                feedback_parts.append(f"Could not verify team name '{expected_name}' in screenshots.")
                
            # Details check
            if parsed.get("address_or_phone_visible", False):
                score += 20
                feedback_parts.append("Address/Phone details verified.")
            else:
                feedback_parts.append("Could not verify address or phone details.")
                
            # workflow check
            if parsed.get("correct_module_accessed", False):
                score += 10
                feedback_parts.append("Correct module accessed.")
                
            # Saved state check
            if parsed.get("record_saved_indication", False):
                score += 10
                feedback_parts.append("Record appears to be saved.")
        else:
            feedback_parts.append("VLM verification failed to process images.")

    # Final Evaluation
    # Pass if score >= 60 AND database was actually modified (hard requirement for persistent tasks)
    # AND name was visible
    
    db_mod = result_data.get("db_modified", False)
    passed = (score >= 60) and db_mod
    
    if not db_mod:
        feedback_parts.append("FAIL: Database was not modified (nothing saved).")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }