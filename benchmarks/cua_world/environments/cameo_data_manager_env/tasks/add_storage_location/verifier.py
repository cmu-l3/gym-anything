#!/usr/bin/env python3
"""
Verifier for CAMEO Data Manager: Add Storage Location task.

Verification Strategy:
1. File System (Anti-Gaming): Check if the CAMEO database file was actually modified during the task.
2. VLM (Visual): Verify the final state shows the correct storage location details in the UI.
   - Location: East Production Building - Tank Farm
   - Type: Above ground tank
   - Amounts: 10000 / 6500

We rely on VLM for content verification because parsing the proprietary CAMEO .4DD database 
without the application's API is unreliable.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_storage_location(traj, env_info, task_info):
    """
    Verify that the agent added the specific storage location to the chemical record.
    """
    # 1. Setup - Get data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Read the result JSON exported by PowerShell
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        # Continue with VLM verification, but penalty for missing file stats
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Components
    score = 0
    feedback_parts = []
    
    # Criterion A: Database Activity (20 points)
    # Check if the database file was modified during the task
    db_modified = task_result.get('db_modified', False)
    app_running = task_result.get('app_running', False)
    
    if db_modified:
        score += 20
        feedback_parts.append("Database updated successfully.")
    else:
        feedback_parts.append("Warning: No changes detected in database file.")
        
    if app_running:
        score += 5
        feedback_parts.append("Application remained open.")
    
    # Criterion B: VLM Content Verification (75 points)
    # We verify the actual data entered using the final screenshot
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No screenshot available for verification."}

    # Define the prompt for the VLM
    prompt = """
    Analyze this screenshot from CAMEO Data Manager.
    
    Goal: Verify if a "Storage Location" has been added to a chemical record.
    
    Look for a section titled "Storage Locations" or a form showing storage details.
    
    Check for these specific values:
    1. Location: "East Production Building" OR "Tank Farm"
    2. Storage Type: "Above ground tank"
    3. Max Amount: "10000" (or 10,000)
    4. Avg Amount: "6500" (or 6,500)
    
    Output JSON:
    {
        "storage_location_visible": true/false,
        "location_name_match": true/false,
        "storage_type_match": true/false,
        "amounts_match": true/false,
        "reasoning": "Explain what you see"
    }
    """
    
    vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
    
    if vlm_response.get('success'):
        parsed = vlm_response.get('parsed', {})
        
        if parsed.get('storage_location_visible'):
            score += 15
            feedback_parts.append("Storage location section visible.")
            
            if parsed.get('location_name_match'):
                score += 20
                feedback_parts.append("Location description matches.")
            else:
                feedback_parts.append("Location description incorrect or not visible.")
                
            if parsed.get('storage_type_match'):
                score += 20
                feedback_parts.append("Storage type matches.")
            
            if parsed.get('amounts_match'):
                score += 20
                feedback_parts.append("Amounts match.")
        else:
            feedback_parts.append("Could not find storage location details in the final view.")
    else:
        feedback_parts.append("Visual verification failed to process.")

    # Criterion C: Trajectory Check (Simulated for robustness - usually VLM looks at frames)
    # We rely on the final state mostly for data entry, but could check frames for the "Add" button click.
    
    # Final Score Calculation
    # Pass threshold: 60 points (Requires DB mod + at least partial visual match)
    passed = score >= 60 and db_modified
    
    if not db_modified and score > 60:
        feedback_parts.append("FAILED: Database was not saved (file not modified).")
        passed = False
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }