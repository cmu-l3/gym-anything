#!/usr/bin/env python3
"""Stub verifier for enter_t4_employment_income task.
Actual verification is done externally via VLM evaluators.
"""

import json
import tempfile
import os


def verify_enter_t4_employment_income(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    score = 0
    feedback = []
    details = {}

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/t4_employment_result.json", temp_path)

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

    # Criterion 2: File was created during task (15 pts)
    if result.get('file_is_new'):
        score += 15
        feedback.append("File timestamp valid")
    else:
        feedback.append("File timestamp check failed")

    # Criterion 3: File contains taxpayer name (15 pts)
    if result.get('contains_jonah') and result.get('contains_smith'):
        score += 15
        feedback.append("Taxpayer name found in file")
    elif result.get('contains_jonah') or result.get('contains_smith'):
        score += 8
        feedback.append("Partial name match")
    else:
        feedback.append("Taxpayer name not found")

    # Criterion 4: File contains income amount (15 pts)
    if result.get('contains_18000'):
        score += 15
        feedback.append("Employment income amount found")
    else:
        feedback.append("Employment income not found in file")

    # Criterion 5: File size indicates substantial data entry (10 pts)
    file_size = result.get('file_size_bytes', 0)
    if file_size > 1000:
        score += 10
        feedback.append(f"File size ({file_size} bytes) indicates data entry")
    else:
        feedback.append(f"File size ({file_size} bytes) too small")

    # Remaining 25 pts reserved for VLM evaluation
    details['vlm_reserved'] = 25

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": details,
        "subscores": {
            "file_saved": 20 if result.get('file_exists') else 0,
            "timestamp_valid": 15 if result.get('file_is_new') else 0,
            "name_present": 15 if (result.get('contains_jonah') and result.get('contains_smith')) else 0,
            "income_present": 15 if result.get('contains_18000') else 0,
            "data_entry_size": 10 if file_size > 1000 else 0,
            "vlm_evaluation": "pending"
        }
    }
