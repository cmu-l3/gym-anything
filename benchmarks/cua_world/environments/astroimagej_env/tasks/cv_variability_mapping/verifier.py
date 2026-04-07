#!/usr/bin/env python3
import json
import tempfile
import os

def verify_cv_variability_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    if result.get("error"):
        feedback.append(f"Internal error during evaluation: {result['error']}")

    # Criterion 1: Average Map (20 points)
    if result.get("avg_map_exists"):
        if result.get("avg_is_correct"):
            score += 20
            feedback.append("Average map exists and is mathematically correct.")
        else:
            score += 10
            feedback.append("Average map exists but pixel values do not match ground truth.")
    else:
        feedback.append("Average map is missing.")

    # Criterion 2: Std Map (20 points)
    if result.get("std_map_exists"):
        if result.get("std_is_correct"):
            score += 20
            feedback.append("Standard Deviation map exists and is mathematically correct.")
        else:
            score += 10
            feedback.append("Standard Deviation map exists but pixel values do not match ground truth.")
    else:
        feedback.append("Standard Deviation map is missing.")

    # Criterion 3: CV Map Generation (25 points)
    if result.get("cv_map_exists"):
        if result.get("cv_is_correct") or result.get("cv_math_is_correct"):
            score += 25
            feedback.append("CV map exists and was correctly computed (STD / AVG).")
        else:
            score += 10
            feedback.append("CV map exists but pixel values indicate incorrect arithmetic.")
    else:
        feedback.append("CV map is missing.")

    # Criterion 4: Mean CV Reported (15 points)
    actual_mean = result.get("actual_mean_cv")
    reported_mean = result.get("reported_mean_cv")
    if result.get("stats_file_exists"):
        if reported_mean is not None and actual_mean is not None:
            # 1% tolerance
            if abs(reported_mean - actual_mean) <= max(0.01, 0.01 * abs(actual_mean)):
                score += 15
                feedback.append(f"Reported mean_cv ({reported_mean}) matches actual mean.")
            else:
                feedback.append(f"Reported mean_cv ({reported_mean}) is incorrect (actual: {actual_mean:.4f}).")
        else:
            feedback.append("mean_cv could not be parsed from statistics file.")
    else:
        feedback.append("Statistics file is missing.")

    # Criterion 5: Max CV Reported (20 points)
    actual_max = result.get("actual_max_cv")
    reported_max = result.get("reported_max_cv")
    if result.get("stats_file_exists"):
        if reported_max is not None and actual_max is not None:
            # 1% tolerance
            if abs(reported_max - actual_max) <= max(0.01, 0.01 * abs(actual_max)):
                score += 20
                feedback.append(f"Reported max_cv ({reported_max}) matches actual max.")
            else:
                feedback.append(f"Reported max_cv ({reported_max}) is incorrect (actual: {actual_max:.4f}).")
        else:
            feedback.append("max_cv could not be parsed from statistics file.")
    
    passed = score >= 65 and result.get("cv_map_exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }