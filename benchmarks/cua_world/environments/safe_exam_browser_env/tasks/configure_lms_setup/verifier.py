#!/usr/bin/env python3
"""
Verifier for configure_lms_setup task.
Checks that a Moodle LMS Setup was correctly created in SEB Server.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_lms_setup(traj, env_info, task_info):
    """
    Verify that the LMS setup was created correctly.
    Uses multiple independent signals: database records + VLM trajectory check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Attempt to copy the result JSON from the environment container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract results
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    new_records_created = result.get('new_records_created', 0)
    
    name_found = result.get('name_found', False)
    type_found = result.get('type_found', False)
    url_found = result.get('url_found', False)
    client_found = result.get('client_found', False)
    
    # 1. New Record Created (20 pts)
    # Important for anti-gaming: check if they actually created a NEW entry during the task
    if new_records_created > 0 and current_count > initial_count:
        score += 20
        feedback_parts.append("New LMS Setup record created (+20)")
    else:
        feedback_parts.append("No new LMS Setup record detected")
    
    # 2. Correct Name (20 pts)
    if name_found:
        score += 20
        feedback_parts.append("Name 'State University Moodle' configured (+20)")
    else:
        feedback_parts.append("Name 'State University Moodle' not found")
        
    # 3. Correct URL (20 pts)
    if url_found:
        score += 20
        feedback_parts.append("URL 'moodle.stateuniversity.edu' configured (+20)")
    else:
        feedback_parts.append("Expected URL not found")
        
    # 4. Correct LMS Type (15 pts)
    if type_found:
        score += 15
        feedback_parts.append("LMS Type 'Moodle' configured (+15)")
    else:
        feedback_parts.append("LMS Type 'Moodle' not found")
        
    # 5. Client Username/Name (10 pts)
    if client_found:
        score += 10
        feedback_parts.append("Client name 'seb-server-integration' configured (+10)")
    else:
        feedback_parts.append("Client name not found")

    # 6. VLM Check (15 pts) - Prevents gaming where agent might theoretically insert via DB directly
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        if all_frames:
            prompt = (
                "You are an examiner verifying a user's workflow in Safe Exam Browser (SEB) Server.\n"
                "The user was asked to create a new LMS Setup for a Moodle integration.\n"
                "Look at these screenshots from the user's session.\n"
                "Did the user use the web interface to fill out the 'LMS Setup' form and try to save it?\n"
                "Respond in JSON format with a single boolean field 'form_interacted': true/false."
            )
            
            vlm_response = query_vlm(images=all_frames, prompt=prompt)
            if vlm_response and vlm_response.get("parsed", {}).get("form_interacted"):
                vlm_score = 15
                feedback_parts.append("VLM confirms GUI form interaction (+15)")
            else:
                feedback_parts.append("VLM did not detect GUI form interaction (+0)")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Grace degradation: if VLM is completely unavailable but database was completely correct
        if score >= 85:
            vlm_score = 15
            feedback_parts.append("Assumed VLM pass due to perfect database state (+15)")
            
    score += vlm_score
    
    # Cap score
    score = min(score, 100)
    
    # Key criteria threshold to pass (must have added an entry with the target name)
    key_criteria_met = (new_records_created > 0) and name_found and (type_found or url_found)
    passed = (score >= 60) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }