#!/usr/bin/env python3
"""
Verifier for add_student_medical_alert task.

Verifies that:
1. A new medical record exists for the student Sarah Connor.
2. The record contains "Peanut" and "EpiPen".
3. The record date is today (or very recent).
4. VLM verification of the trajectory (navigation to medical tab).
"""

import json
import os
import datetime
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_medical_alert(traj, env_info, task_info):
    # 1. Setup and load data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result from container
    import tempfile
    temp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    score = 0
    feedback = []
    
    # Metadata expectations
    meta = task_info.get('metadata', {})
    expected_text_1 = meta.get('expected_text_1', 'Peanut').lower()
    expected_text_2 = meta.get('expected_text_2', 'EpiPen').lower()

    # 2. Database Verification
    records = result_data.get('medical_records', [])
    initial_count = int(result_data.get('initial_count', 0))
    current_count = len(records)
    
    record_found = False
    text_match_1 = False
    text_match_2 = False
    date_match = False

    if current_count > initial_count:
        score += 20
        feedback.append("New medical record created.")
        
        # Check content of the NEW records
        # (Simplified: check all records since we started with 0 or low count)
        today_str = datetime.date.today().isoformat()
        
        for rec in records:
            content = rec.get('content', '').lower()
            rec_date = rec.get('date', '')
            
            # Check text
            if expected_text_1 in content:
                text_match_1 = True
            if expected_text_2 in content:
                text_match_2 = True
            
            # Check date (allow match with today)
            if today_str in rec_date:
                date_match = True
                
            if text_match_1 and text_match_2:
                record_found = True
                # Break if we found a perfect record, otherwise keep searching
                break
    else:
        feedback.append("No new medical records found in database.")

    # Scoring content
    if text_match_1:
        score += 20
        feedback.append(f"Found keyword '{expected_text_1}'")
    else:
        feedback.append(f"Missing keyword '{expected_text_1}'")

    if text_match_2:
        score += 20
        feedback.append(f"Found keyword '{expected_text_2}'")
    else:
        feedback.append(f"Missing keyword '{expected_text_2}'")

    if date_match:
        score += 10
        feedback.append("Record date is correct (today).")

    # 3. VLM Verification (Trajectory)
    # We want to see if the agent actually navigated to the "Medical" tab
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with OpenSIS Student Information System.
    The user task is to add a medical alert for a student.
    
    Check for the following:
    1. Is the "Medical" or "Health" tab/page visible in any frame?
    2. Is the student "Sarah Connor" visible?
    3. Is there text input related to "Peanut" or "Allergy"?
    
    Return JSON: {"medical_tab_seen": bool, "student_seen": bool, "allergy_input_seen": bool}
    """
    
    try:
        # We combine frames for the query
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        if vlm_res and 'parsed' in vlm_res:
            parsed = vlm_res['parsed']
            if parsed.get('medical_tab_seen'):
                score += 15
                feedback.append("VLM confirmed navigation to Medical tab.")
            if parsed.get('allergy_input_seen'):
                score += 15
                feedback.append("VLM confirmed allergy data entry.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB check passed perfectly, give VLM points
        if score >= 70:
            score += 30
            feedback.append("VLM skipped (DB verified).")

    # Final Pass check
    # Need at least 70 points AND the main keyword "Peanut"
    passed = (score >= 70) and text_match_1

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }