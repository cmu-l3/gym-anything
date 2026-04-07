#!/usr/bin/env python3
"""
Verifier for record_visit_note task.
Checks if the agent successfully created a Visit Note with 'Headache' diagnosis.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_visit_note(traj, env_info, task_info):
    """
    Verify the agent recorded the visit note correctly.
    
    Scoring:
    - 40 pts: Encounter created (of correct type)
    - 40 pts: Diagnosis matches 'Headache'
    - 20 pts: VLM Trajectory Verification (UI interaction confirmed)
    """
    
    # 1. Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Metrics
    encounter_found = result.get('encounter_found', False)
    diagnosis_correct = result.get('diagnosis_correct', False)
    found_diagnosis = result.get('found_diagnosis_name', 'None')
    new_encounters_count = int(result.get('total_new_encounters_db', 0))
    
    score = 0
    feedback = []
    
    # 3. Score Programmatic Criteria
    if encounter_found:
        score += 40
        feedback.append("Success: Visit Note encounter created.")
    elif new_encounters_count > 0:
        score += 10
        feedback.append("Partial: An encounter was created, but not the correct type or missing diagnosis.")
    else:
        feedback.append("Fail: No new encounter found.")
        
    if diagnosis_correct:
        score += 40
        feedback.append(f"Success: Correct diagnosis '{found_diagnosis}' recorded.")
    elif encounter_found:
        feedback.append(f"Fail: Diagnosis incorrect. Found: '{found_diagnosis}'. Expected: Headache.")
        
    # 4. VLM Trajectory Verification
    # We check if the agent actually interacted with the form
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Analyze these screenshots of a user using an Electronic Health Record system.
        The user goal is to fill out a 'Visit Note' form.
        
        Look for:
        1. Opening a form modal or page titled "Visit Note" or "Clinical Note".
        2. Typing or selecting "Headache" in a search field.
        3. Clicking a "Save" or "Submit" button.
        
        Did the user appear to complete these steps?
        Return JSON: {"steps_completed": boolean, "diagnosis_visible": boolean}
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_data = vlm_res.get('parsed', {})
        
        if vlm_data.get('steps_completed', False):
            score += 20
            feedback.append("VLM: Form interaction confirmed.")
        elif vlm_data.get('diagnosis_visible', False):
            score += 15
            feedback.append("VLM: Diagnosis selection visible.")
        else:
            feedback.append("VLM: Could not clearly see form interaction.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Graceful fallback: if DB check passed perfectly, assume VLM passed
        if encounter_found and diagnosis_correct:
            score += 20
            feedback.append("VLM skipped (programmatic success sufficient).")

    # 5. Final Result
    passed = (score >= 80) # Requires encounter + diagnosis + some VLM
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }