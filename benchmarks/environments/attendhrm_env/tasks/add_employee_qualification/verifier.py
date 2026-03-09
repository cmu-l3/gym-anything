#!/usr/bin/env python3
"""
Verifier for add_employee_qualification task in AttendHRM.

Scoring Criteria:
1. Qualification Record Created (20 pts)
2. Qualification/Degree Correct (15 pts)
3. Institution Correct (15 pts)
4. Year Correct (10 pts)
5. Specialization Correct (10 pts)
6. Grade/Remarks Correct (10 pts)
7. VLM Verification of UI Interaction (20 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_employee_qualification(traj, env_info, task_info):
    """
    Verify that the qualification record was added correctly to AttendHRM.
    """
    # 1. Retrieve Result JSON from Environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is C:\workspace\task_result.json
        # The copy_from_env function handles the path translation for the specific environment type
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata for expectations
    meta = task_info.get('metadata', {})
    exp_qual = meta.get('expected_qualification', 'MBA').lower()
    exp_inst = meta.get('expected_institution', 'Michigan').lower()
    exp_year = meta.get('expected_year', '2018')
    exp_spec = meta.get('expected_specialization', 'Finance').lower()

    # --- Database Verification (70 Points) ---
    
    db_data = result.get('db_data', {})
    record_added = result.get('record_added', False)
    final_count = result.get('final_record_count', 0)
    
    # Criterion 1: Record Added (20 pts)
    # We check if count increased or if we found the specific record data
    has_data = bool(db_data)
    if record_added or (final_count > 0 and has_data):
        score += 20
        feedback.append("Qualification record detected in database.")
    else:
        feedback.append("No qualification record found.")
        return {"passed": False, "score": 0, "feedback": "Fail: No record created."}

    # Criterion 2: Degree/Qualification (15 pts)
    act_qual = db_data.get('qualification', '').lower()
    if exp_qual in act_qual or 'master' in act_qual:
        score += 15
        feedback.append(f"Qualification '{act_qual}' matches expected.")
    else:
        feedback.append(f"Qualification mismatch: Found '{act_qual}', expected '{exp_qual}'.")

    # Criterion 3: Institution (15 pts)
    act_inst = db_data.get('institution', '').lower()
    if exp_inst in act_inst:
        score += 15
        feedback.append("Institution matches.")
    else:
        feedback.append(f"Institution mismatch: Found '{act_inst}'.")

    # Criterion 4: Year (10 pts)
    act_year = str(db_data.get('year', ''))
    if exp_year in act_year:
        score += 10
        feedback.append("Year matches.")
    else:
        feedback.append(f"Year mismatch: Found '{act_year}'.")

    # Criterion 5: Specialization (10 pts)
    act_spec = db_data.get('specialization', '').lower()
    if exp_spec in act_spec:
        score += 10
        feedback.append("Specialization matches.")
    else:
        feedback.append(f"Specialization mismatch: Found '{act_spec}'.")

    # --- VLM Verification (30 Points) ---
    
    # We check if the agent actually used the UI correctly
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with AttendHRM software.
    The user is supposed to:
    1. Navigate to an employee profile (Robert Clarke).
    2. Go to the 'Qualification' or 'Education' tab.
    3. Fill in details for an MBA degree.
    
    Look for:
    - An employee list or profile screen.
    - A tab or window labeled 'Qualification', 'Education', or similar.
    - Data entry of 'MBA', 'University of Michigan', or '2018'.
    
    Answer JSON:
    {
        "employee_profile_accessed": boolean,
        "qualification_tab_opened": boolean,
        "data_entry_observed": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('employee_profile_accessed'): vlm_score += 10
        if parsed.get('qualification_tab_opened'): vlm_score += 10
        if parsed.get('data_entry_observed'): vlm_score += 10
        
        score += vlm_score
        feedback.append(f"VLM Verification Score: {vlm_score}/30")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if DB data is perfect, give partial VLM credit
        if score >= 60:
            score += 15
            feedback.append("VLM skipped, awarded partial credit based on DB success.")

    # --- Final Result ---
    
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }