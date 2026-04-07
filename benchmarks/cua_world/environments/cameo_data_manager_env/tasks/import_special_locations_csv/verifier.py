#!/usr/bin/env python3
"""
Verifier for CAMEO Data Manager: Import Special Locations.

Strategy:
1. Programmatic: Check if the specific school names exist in the CAMEO backend files (exported via JSON).
2. Visual (VLM): Verify the agent used the mapping wizard correctly and the final list is visible.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_special_locations(traj, env_info, task_info):
    """
    Verifies that the CSV data was correctly imported into CAMEO.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_count', 5)
    
    # 1. Programmatic Check (Data persistence)
    # ----------------------------------------
    score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Path is inside the Windows container
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        result_data = {"found_count": 0, "cameo_running": False}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    found_count = result_data.get("found_count", 0)
    
    # Scoring for data presence (Max 50 points)
    # 10 points per record found
    data_score = min(50, found_count * 10)
    score += data_score
    feedback_parts.append(f"Found {found_count}/{expected_count} records in database storage.")

    # 2. VLM Verification (Workflow & UI)
    # -----------------------------------
    # We need to verify:
    # A) The mapping dialog was used (to ensure fields like MUNI -> City were mapped)
    # B) The final list shows the schools with correct columns
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    prompt = """
    You are verifying a data import task in "CAMEO Data Manager".
    
    The user was supposed to import a CSV file and map these fields:
    - FAC_NAME -> Name
    - ADDR_1 -> Street Address
    - MUNI -> City
    
    Look at the image sequence. 
    1. Do you see an "Import" dialog where fields are being mapped?
    2. In the final result (last image), do you see a list of schools?
    3. Specifically, do you see "Horizon Science Academy" listed?
    4. Does the city column show "Chicago" (and NOT "MUNI" or blank)?
    
    Return JSON:
    {
        "mapping_dialog_seen": true/false,
        "school_list_visible": true/false,
        "horizon_academy_seen": true/false,
        "city_column_correct": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    # We use the final screenshot primarily, but frames help catch the mapping step
    vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("mapping_dialog_seen"):
            vlm_score += 15
            feedback_parts.append("Confirmed usage of Import Mapping dialog.")
        
        if parsed.get("school_list_visible"):
            vlm_score += 15
            feedback_parts.append("Special Locations list is visible.")
            
        if parsed.get("horizon_academy_seen"):
            vlm_score += 10
            feedback_parts.append("Visual confirmation of imported record.")
            
        if parsed.get("city_column_correct"):
            vlm_score += 10
            feedback_parts.append("City field mapped correctly.")
    else:
        feedback_parts.append("VLM verification failed to process images.")

    score += vlm_score

    # 3. Final Determination
    # ----------------------
    passed = (score >= 70) and (found_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }