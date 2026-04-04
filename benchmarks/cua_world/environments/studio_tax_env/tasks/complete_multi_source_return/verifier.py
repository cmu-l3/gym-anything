#!/usr/bin/env python3
"""Stub verifier for complete_multi_source_return task.
Actual verification is done externally via VLM evaluators.
"""

import json
import tempfile
import os


def verify_complete_multi_source_return(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/multi_source_result.json", temp_path)

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

    # Criterion 2: File timestamp valid (10 pts)
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("File timestamp failed")

    # Criterion 3: Taxpayer name present (5 pts)
    if result.get('contains_han') and result.get('contains_park'):
        score += 5
        feedback.append("Taxpayer name found")
    else:
        feedback.append("Taxpayer name not found")

    # Criterion 4: Both T4 employer amounts present (15 pts)
    t4_1 = result.get('contains_32000', False)
    t4_2 = result.get('contains_28000', False)
    if t4_1 and t4_2:
        score += 15
        feedback.append("Both T4 slips found")
    elif t4_1 or t4_2:
        score += 8
        feedback.append("One T4 slip found")
    else:
        feedback.append("T4 slips not found")

    # Criterion 5: Total income (10 pts)
    if result.get('contains_60000'):
        score += 10
        feedback.append("Total income correct")
    else:
        feedback.append("Total income not found")

    # Criterion 6: Medical expenses (10 pts)
    if result.get('contains_3830') or result.get('contains_medical'):
        score += 10
        feedback.append("Medical expenses found")
    else:
        feedback.append("Medical expenses not found")

    # Criterion 7: Charitable donations (10 pts)
    if result.get('contains_1200_donations') or result.get('contains_charit'):
        score += 10
        feedback.append("Charitable donations found")
    else:
        feedback.append("Donations not found")

    # 25 pts reserved for VLM evaluation

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25},
        "subscores": {
            "file_saved": 15 if result.get('file_exists') else 0,
            "timestamp_valid": 10 if result.get('file_is_new') else 0,
            "name_present": 5 if (result.get('contains_han') and result.get('contains_park')) else 0,
            "both_t4s": 15 if (t4_1 and t4_2) else (8 if (t4_1 or t4_2) else 0),
            "total_income": 10 if result.get('contains_60000') else 0,
            "medical": 10 if (result.get('contains_3830') or result.get('contains_medical')) else 0,
            "donations": 10 if (result.get('contains_1200_donations') or result.get('contains_charit')) else 0,
            "vlm_evaluation": "pending"
        }
    }
