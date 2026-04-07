#!/usr/bin/env python3
"""
Verifier for mark_student_retention@1

Checks if the student "Robert Failson" has been marked for retention in the database.
Uses VLM trajectory analysis to verify the user navigated to the Enrollment section.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mark_student_retention(traj, env_info, task_info):
    """
    Verify student retention status update.
    
    Criteria:
    1. Student record must exist (Basic check) - 20 pts
    2. 'rolling_option' in DB must be 'Retain' (Primary outcome) - 50 pts
    3. VLM verifies user accessed Enrollment tab (Process check) - 20 pts
    4. Data Integrity (Name/Grade didn't change randomly) - 10 pts
    """
    
    # 1. Setup Result Reading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Database Verification
    student_found = result.get('student_found', False)
    student_data = result.get('student_data', {})
    
    if not student_found:
        return {"passed": False, "score": 0, "feedback": "Target student 'Robert Failson' not found in database."}
    
    score += 20
    feedback.append("Student record found.")
    
    # Check Retention Status
    # Acceptable values for retention often include 'Retain', 'Retention', or specific ID codes
    # We check for the string 'Retain' (case insensitive)
    rolling_val = str(student_data.get('rolling_option', '')).lower()
    
    if 'retain' in rolling_val:
        score += 50
        feedback.append(f"Success: Student marked for retention (Value: {student_data.get('rolling_option')}).")
    else:
        feedback.append(f"Fail: Student rolling option is '{student_data.get('rolling_option')}', expected 'Retain'.")

    # Check Data Integrity
    # Name should still be Robert Failson
    if student_data.get('first_name') == 'Robert' and student_data.get('last_name') == 'Failson':
        score += 10
        feedback.append("Data Integrity: Student name preserved.")
    else:
        feedback.append("Warning: Student name seems modified.")

    # 3. VLM Verification (Trajectory Analysis)
    # We want to ensure they actually used the UI correctly, not just SQL injection (unlikely but good practice)
    # or that they navigated to the specific enrollment section.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    vlm_prompt = """
    Analyze these screenshots of a user interacting with OpenSIS Student Information System.
    The goal was to mark a student for retention.
    
    Look for:
    1. A student profile/detail page.
    2. A tab or section labeled "Enrollment", "Enrollment Info", or "Student Enrollment".
    3. A dropdown or setting labeled "Rolling Options", "Next Grade", or "Retain".
    
    Did the user navigate to the Enrollment Information section of a student record?
    Reply with JSON: {"enrollment_accessed": boolean, "reasoning": "string"}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result and isinstance(vlm_result, dict):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('enrollment_accessed', False):
            score += 20
            vlm_passed = True
            feedback.append("VLM Verification: Enrollment section access confirmed.")
        else:
            feedback.append(f"VLM Verification: Could not confirm navigation to Enrollment section. ({parsed.get('reasoning', 'No reason provided')})")
    else:
        feedback.append("VLM Verification: Failed to analyze frames.")

    # 4. Final Scoring
    # Pass if Score >= 90 (Requires finding student + Setting Retain + (Integrity OR VLM))
    # We strictly require the DB change.
    
    passed = (score >= 90) and ('retain' in rolling_val)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }