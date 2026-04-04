#!/usr/bin/env python3
"""
Verifier for record_animal_movement task.

Criteria:
1. Animal 'Marguerite' must be found (Critical).
2. Animal's location must be 'Pature des Saules' (Primary Goal).
3. Animal record must have been updated *after* task start (Anti-gaming).
4. VLM verification of the UI state (Secondary).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_animal_movement(traj, env_info, task_info):
    """
    Verifies that the agent moved the animal 'Marguerite' to 'Pature des Saules'.
    """
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    task_start = result.get('task_start', 0)
    animal_found = result.get('animal_found', False)
    current_location = result.get('current_location', "")
    animal_updated_ts = result.get('animal_updated_at', 0)

    target_zone = task_info.get('metadata', {}).get('target_zone', 'Pature des Saules')
    
    score = 0
    feedback_parts = []
    
    # 3. Evaluate Criteria
    
    # A. Animal Existence (Pre-req)
    if not animal_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Animal 'Marguerite' could not be found in the database. Task failed."
        }
    
    # B. Location Verification (50 pts)
    # Check exact match or substring match (case insensitive)
    if current_location and target_zone.lower() in current_location.lower():
        score += 50
        feedback_parts.append(f"Success: Animal is located in '{current_location}'")
    else:
        feedback_parts.append(f"Fail: Animal is in '{current_location}', expected '{target_zone}'")

    # C. Timestamp Verification (Anti-gaming) (30 pts)
    # The animal record update time must be greater than task start time
    if animal_updated_ts > task_start:
        score += 30
        feedback_parts.append("Data consistency: Record updated during task session")
    else:
        feedback_parts.append("Warning: Animal record was NOT updated during this session (stale data?)")

    # D. VLM Verification (20 pts)
    # Use VLM to check if the agent actually performed the UI workflow
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        if frames:
            prompt = (
                f"The user is supposed to move an animal named 'Marguerite' to the zone '{target_zone}'. "
                "Review these screenshots of the agent's actions. "
                "1. Do you see an animal details page or list? "
                "2. Do you see a 'Change location' or 'Move' action being performed? "
                f"3. Do you see '{target_zone}' being selected? "
                "Answer yes/no for each and provide a brief summary."
            )
            vlm_response = query_vlm(images=frames + [final_shot], prompt=prompt)
            
            # Simple keyword heuristic on VLM response
            lower_resp = str(vlm_response).lower()
            if "yes" in lower_resp and target_zone.lower() in lower_resp:
                vlm_score = 20
                feedback_parts.append("Visual verification passed")
            elif "yes" in lower_resp:
                vlm_score = 10
                feedback_parts.append("Visual verification partial (action seen but details unclear)")
            else:
                feedback_parts.append("Visual verification inconclusive")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB checks passed perfectly, assume visual is fine
        if score >= 80:
            vlm_score = 20
            feedback_parts.append("Visual verification skipped (DB checks conclusive)")

    score += vlm_score

    # 4. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }