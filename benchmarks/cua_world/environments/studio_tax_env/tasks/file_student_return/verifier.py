#!/usr/bin/env python3
"""Stub verifier for file_student_return task.
Actual verification is done externally via VLM evaluators.
"""

import json
import tempfile
import os


def verify_file_student_return(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/student_return_result.json", temp_path)

        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Criterion 1: File exists and is non-empty (15 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 100:
        score += 15
        feedback.append("Return file saved")
    else:
        feedback.append("No return file found")

    # Criterion 2: File created during task (10 pts)
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("File timestamp failed")

    # Criterion 3: Taxpayer name present (10 pts)
    if result.get('contains_farah') and result.get('contains_awan'):
        score += 10
        feedback.append("Taxpayer name found")
    else:
        feedback.append("Taxpayer name not found")

    # Criterion 4: Employment income present (10 pts)
    if result.get('contains_10000'):
        score += 10
        feedback.append("T4 income found")
    else:
        feedback.append("T4 income not found")

    # Criterion 5: ODSP social assistance (10 pts)
    if result.get('contains_14000'):
        score += 10
        feedback.append("ODSP amount found")
    else:
        feedback.append("ODSP not found")

    # Criterion 6: Scholarship or RESP data (10 pts)
    scholarship = result.get('contains_4500', False) or result.get('contains_scholarship', False)
    resp = result.get('contains_5700', False)
    if scholarship and resp:
        score += 10
        feedback.append("Scholarship + RESP found")
    elif scholarship or resp:
        score += 5
        feedback.append("Partial scholarship/RESP")
    else:
        feedback.append("Scholarship/RESP not found")

    # Criterion 7: Tuition data (10 pts)
    if result.get('contains_6000') or result.get('contains_tuition'):
        score += 10
        feedback.append("Tuition data found")
    else:
        feedback.append("Tuition not found")

    # 25 pts reserved for VLM evaluation

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25},
        "subscores": {
            "file_saved": 15 if result.get('file_exists') else 0,
            "timestamp_valid": 10 if result.get('file_is_new') else 0,
            "name_present": 10 if (result.get('contains_farah') and result.get('contains_awan')) else 0,
            "t4_income": 10 if result.get('contains_10000') else 0,
            "odsp": 10 if result.get('contains_14000') else 0,
            "scholarship_resp": 10 if (scholarship and resp) else (5 if (scholarship or resp) else 0),
            "tuition": 10 if (result.get('contains_6000') or result.get('contains_tuition')) else 0,
            "vlm_evaluation": "pending"
        }
    }
