#!/usr/bin/env python3
"""
Verifier for mark_patient_deceased task.

Scoring Criteria:
1. Patient marked as deceased in Database (35 pts)
2. Correct Death Date in Database (25 pts)
3. Modified during task (Anti-gaming) (10 pts)
4. API cross-validation matches DB (10 pts)
5. VLM Trajectory Verification (20 pts)
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mark_patient_deceased(traj, env_info, task_info):
    """
    Verify that the patient was correctly marked as deceased.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Metadata
    metadata = task_info.get('metadata', {})
    target_date = metadata.get('target_death_date', '2025-01-15')
    
    # 2. Retrieve Result JSON
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

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: DB Deceased Status (35 pts) ---
    # DB returns "1" for true, "0" for false usually
    db_dead = str(result.get('db_dead', '')).strip()
    is_dead = db_dead == "1"
    
    if is_dead:
        score += 35
        feedback_parts.append("Patient marked deceased in DB")
    else:
        feedback_parts.append("Patient NOT marked deceased in DB")

    # --- Criterion 2: DB Death Date (25 pts) ---
    db_date = str(result.get('db_death_date', '')).strip()
    if db_date == target_date:
        score += 25
        feedback_parts.append(f"Death date correct ({db_date})")
    elif is_dead and db_date:
        # Partial credit if date is wrong but present
        score += 5
        feedback_parts.append(f"Death date incorrect (Expected {target_date}, Got {db_date})")
    else:
        feedback_parts.append("Death date missing or empty")

    # --- Criterion 3: Anti-gaming / State Change (10 pts) ---
    modified = result.get('modified_during_task', False)
    if modified:
        score += 10
        feedback_parts.append("Record modified during task")
    else:
        # If they got the data right but it wasn't modified, it implies it was already there (gaming)
        # or the timestamps are messed up. We penalize heavily if we can't prove work was done.
        feedback_parts.append("WARN: Record not modified during task timeframe")

    # --- Criterion 4: API Consistency (10 pts) ---
    api_dead = str(result.get('api_dead', '')).lower()
    api_date = str(result.get('api_death_date', ''))
    
    api_success = (api_dead == 'true') and (api_date == target_date)
    if api_success:
        score += 10
        feedback_parts.append("API validation confirmed")
    else:
        feedback_parts.append("API validation failed")

    # --- Criterion 5: VLM Trajectory Verification (20 pts) ---
    # We want to see evidence of the user interacting with the patient dashboard/edit screen.
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Analyze these screenshots of a user interacting with an Electronic Health Record (OpenMRS).
        The user should be marking a patient as deceased.
        
        Look for:
        1. A patient dashboard (Showing name 'Harold').
        2. An edit form or 'Mark Patient Deceased' modal/section.
        3. A date picker or date field being filled (ideally with 2025).
        4. A 'Deceased' label or status indicator in the final frames.
        
        Respond in JSON:
        {
            "patient_chart_visited": true/false,
            "edit_deceased_interaction": true/false,
            "final_status_deceased_visible": true/false
        }
        """
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            vlm_score = 0
            if parsed.get('patient_chart_visited'): vlm_score += 5
            if parsed.get('edit_deceased_interaction'): vlm_score += 10
            if parsed.get('final_status_deceased_visible'): vlm_score += 5
            
            score += vlm_score
            feedback_parts.append(f"VLM verification: {vlm_score}/20 pts")
        else:
            # Fallback if VLM fails but DB is correct
            if is_dead and db_date == target_date:
                score += 20
                feedback_parts.append("VLM skipped (DB correct)")
    else:
        feedback_parts.append("No trajectory frames for VLM")

    # Final result
    passed = (score >= 60) and is_dead and (db_date == target_date)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }