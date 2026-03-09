#!/usr/bin/env python3
"""Stub verifier for enter_investment_income task.
Actual verification is done externally via VLM evaluators.
"""

import json
import tempfile
import os


def verify_enter_investment_income(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/investment_result.json", temp_path)

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

    # Criterion 3: Taxpayer name present (10 pts)
    if result.get('contains_maria') and result.get('contains_chen'):
        score += 10
        feedback.append("Taxpayer name found")
    else:
        feedback.append("Taxpayer name not found")

    # Criterion 4: Employment income (10 pts)
    if result.get('contains_65000'):
        score += 10
        feedback.append("Employment income found")
    else:
        feedback.append("Employment income not found")

    # Criterion 5: Dividend data (10 pts)
    div_found = result.get('contains_3200', False) or result.get('contains_dividend', False)
    grossup_found = result.get('contains_4416', False)
    if div_found and grossup_found:
        score += 10
        feedback.append("Dividends with gross-up found")
    elif div_found:
        score += 5
        feedback.append("Dividend data partial")
    else:
        feedback.append("Dividend data not found")

    # Criterion 6: Capital gains or interest (10 pts)
    capgain = result.get('contains_15800', False)
    interest = result.get('contains_1500', False)
    if capgain and interest:
        score += 10
        feedback.append("Capital gains + interest found")
    elif capgain or interest:
        score += 5
        feedback.append("Partial investment data")
    else:
        feedback.append("Investment data not found")

    # Criterion 7: RRSP contribution (10 pts)
    if result.get('contains_5000'):
        score += 10
        feedback.append("RRSP contribution found")
    else:
        feedback.append("RRSP not found")

    # 25 pts reserved for VLM evaluation

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25},
        "subscores": {
            "file_saved": 15 if result.get('file_exists') else 0,
            "timestamp_valid": 10 if result.get('file_is_new') else 0,
            "name_present": 10 if (result.get('contains_maria') and result.get('contains_chen')) else 0,
            "employment": 10 if result.get('contains_65000') else 0,
            "dividends": 10 if (div_found and grossup_found) else (5 if div_found else 0),
            "investments": 10 if (capgain and interest) else (5 if (capgain or interest) else 0),
            "rrsp": 10 if result.get('contains_5000') else 0,
            "vlm_evaluation": "pending"
        }
    }
