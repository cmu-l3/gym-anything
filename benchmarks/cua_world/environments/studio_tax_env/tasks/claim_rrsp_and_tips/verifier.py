#!/usr/bin/env python3
"""Stub verifier for claim_rrsp_and_tips task.
Actual verification is done externally via VLM evaluators.
"""

import json
import tempfile
import os


def verify_claim_rrsp_and_tips(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/rrsp_tips_result.json", temp_path)

        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Criterion 1: File exists and is non-empty (20 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 100:
        score += 20
        feedback.append("Return file saved")
    else:
        feedback.append("No return file found")

    # Criterion 2: File created during task (15 pts)
    if result.get('file_is_new'):
        score += 15
        feedback.append("File timestamp valid")
    else:
        feedback.append("File timestamp failed")

    # Criterion 3: Taxpayer name present (10 pts)
    if result.get('contains_terry') and result.get('contains_lee'):
        score += 10
        feedback.append("Taxpayer name found")
    else:
        feedback.append("Taxpayer name not found")

    # Criterion 4: Employment income present (10 pts)
    if result.get('contains_12000'):
        score += 10
        feedback.append("Employment income found")
    else:
        feedback.append("Employment income not found")

    # Criterion 5: Tips or RRSP data present (10 pts)
    tips_found = result.get('contains_1000', False)
    rrsp_found = result.get('contains_540', False) or result.get('contains_rrsp', False)
    if tips_found and rrsp_found:
        score += 10
        feedback.append("Tips and RRSP data found")
    elif tips_found or rrsp_found:
        score += 5
        feedback.append("Partial tips/RRSP data")
    else:
        feedback.append("Tips/RRSP data not found")

    # Criterion 6: File size indicates complete data entry (10 pts)
    if result.get('file_size_bytes', 0) > 1000:
        score += 10
        feedback.append("File size indicates data entry")
    else:
        feedback.append("File size too small")

    # 25 pts reserved for VLM evaluation

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25},
        "subscores": {
            "file_saved": 20 if result.get('file_exists') else 0,
            "timestamp_valid": 15 if result.get('file_is_new') else 0,
            "name_present": 10 if (result.get('contains_terry') and result.get('contains_lee')) else 0,
            "income_present": 10 if result.get('contains_12000') else 0,
            "tips_rrsp": 10 if (tips_found and rrsp_found) else (5 if (tips_found or rrsp_found) else 0),
            "data_size": 10 if result.get('file_size_bytes', 0) > 1000 else 0,
            "vlm_evaluation": "pending"
        }
    }
