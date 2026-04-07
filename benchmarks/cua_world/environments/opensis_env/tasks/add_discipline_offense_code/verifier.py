#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_discipline_offense_code(traj, env_info, task_info):
    """
    Verify that the 'Cyberbullying' offense code was added to OpenSIS.
    
    Verification Logic:
    1. Database: Check if a record with title 'Cyberbullying' exists.
    2. Anti-Gaming: Check if the record ID is greater than the ID at task start.
    3. VLM: Check trajectory to ensure UI navigation to 'School Setup' or 'Discipline'.
    """
    
    # 1. Setup & Read Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Variables
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Record Exists (50 pts) ---
    record_found = result.get('record_found', False)
    record_title = result.get('record_details', {}).get('title', '')
    
    if record_found and 'cyberbullying' in record_title.lower():
        score += 50
        feedback_parts.append("✅ Database record found for 'Cyberbullying'.")
    else:
        feedback_parts.append("❌ No database record found for 'Cyberbullying'.")
        # Early exit if core objective failed
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # --- Criterion 2: Anti-Gaming / Freshness (25 pts) ---
    is_new_record = result.get('is_new_record', False)
    if is_new_record:
        score += 25
        feedback_parts.append("✅ Record was created during the task session.")
    else:
        feedback_parts.append("⚠️ Record ID indicates it might have existed prior to task start.")

    # --- Criterion 3: VLM Trajectory Verification (25 pts) ---
    # We want to confirm they didn't just run a SQL injection or URL hack (though unlikely).
    # We look for the "School Setup" or "Discipline" menus in the visual history.
    
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        if frames:
            prompt = (
                "You are auditing an agent using OpenSIS student information system. "
                "The task was to navigate to 'School Setup' and add a discipline code. "
                "Look at these screenshots of the agent's session. "
                "Do you see the agent navigating menus like 'School Setup', 'Discipline', or 'System Configuration'? "
                "Do you see a form for adding a code/field? "
                "Answer 'YES' or 'NO' and explain."
            )
            
            # Combine frames into the query
            vlm_response = query_vlm(images=frames, prompt=prompt)
            
            # Simple heuristic parsing of VLM response
            explanation = vlm_response.get('parsed', {}).get('reasoning', '') or vlm_response.get('text', '')
            
            # If the VLM is positive about navigation
            if "YES" in explanation.upper() or "SCHOOL SETUP" in explanation.upper():
                score += 25
                feedback_parts.append("✅ Visual trajectory confirms menu navigation.")
            else:
                # Fallback points if we have the record but VLM is unsure (maybe they were fast)
                score += 10 
                feedback_parts.append(f"⚠️ Visual verification inconclusive, but database record is valid. (VLM said: {explanation[:50]}...)")
        else:
            # If no frames available (shouldn't happen), give benefit of doubt if DB record is new
            if is_new_record:
                score += 25
                feedback_parts.append("⚠️ No trajectory frames, trusting database evidence.")
                
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # If VLM fails but DB is good, we still pass but with slightly lower confidence score
        score += 10
        feedback_parts.append("⚠️ VLM check skipped due to error.")

    # 4. Final Assessment
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }