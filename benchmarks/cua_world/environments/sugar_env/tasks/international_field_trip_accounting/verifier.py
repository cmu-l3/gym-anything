#!/usr/bin/env python3
"""Verifier for international_field_trip_accounting task."""

import json
import os
import tempfile

def verify_international_field_trip_accounting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/trip_accounting_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Script exists (10 pts)
    if result.get('script_exists') and result.get('script_size', 0) > 100:
        score += 10
        feedback.append("trip_calculator.py exists with content")
    else:
        feedback.append("trip_calculator.py missing or empty")

    # Criterion 2: Report exists (10 pts)
    if result.get('output_exists'):
        if result.get('output_modified'):
            score += 10
            feedback.append("trip_financial_summary.txt created/modified")
        else:
            score += 5
            feedback.append("trip_financial_summary.txt exists but mtime check failed")
    else:
        feedback.append("FAIL: trip_financial_summary.txt not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    ground_truth = result.get('ground_truth', {})
    agent_parsed = result.get('agent_parsed', {})
    
    if result.get('error'):
        feedback.append(f"Export script error: {result['error']}")

    def check_value(name, pts):
        gt_val = ground_truth.get(name, 0.0)
        agent_val = agent_parsed.get(name, None)
        if agent_val is not None:
            if abs(gt_val - agent_val) <= 0.10:
                feedback.append(f"{name} correct (${agent_val:.2f})")
                return pts
            else:
                feedback.append(f"{name} incorrect (expected ~${gt_val:.2f}, got ${agent_val:.2f})")
                return 0
        else:
            feedback.append(f"{name} value not found in output")
            return 0

    # Total Cost Correct (30 pts)
    total_score = check_value("Total", 30)
    score += total_score
    total_correct = (total_score == 30)

    # Categories Correct (10+10+20+10 = 50 pts)
    score += check_value("Transport", 10)
    score += check_value("Accommodation", 10)
    # Food is worth 20 points because it includes the randomized Airport Coffee
    score += check_value("Food", 20)
    score += check_value("Activities", 10)

    # Pass: >= 70 AND total cost is correct
    passed = score >= 70 and total_correct and result.get('output_exists', False)

    if passed:
        feedback.append("Financial summary report is correct!")
    else:
        feedback.append(f"Score {score}/100. Check calculations and formatting.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_exists": result.get('script_exists', False),
            "output_exists": result.get('output_exists', False),
            "total_correct": total_correct
        }
    }