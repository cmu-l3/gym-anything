#!/usr/bin/env python3
import json
import os
import tempfile
import re
import math

def verify_mediation_analysis(traj, env_info, task_info):
    """
    Verifies the Baron & Kenny mediation analysis task.
    Checks:
    1. Existence of .omv project file created during task.
    2. Existence of text report.
    3. Accuracy of reported coefficients against ground truth (calculated from data).
    """
    
    # 1. Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable."}
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Unpack Data
    omv_valid = result_data.get("omv_valid_timestamp", False)
    report_exists = result_data.get("report_exists", False)
    report_text = result_data.get("report_content", "").lower()
    ground_truth = result_data.get("ground_truth", {})
    
    # Criterion 1: Jamovi Project File (20 pts)
    if omv_valid:
        score += 20
        feedback.append("Jamovi project file saved correctly.")
    else:
        feedback.append("Jamovi project file missing or not saved during task.")

    # Criterion 2: Report Existence (10 pts)
    if report_exists:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion 3: Statistical Accuracy (70 pts)
    # We look for the ground truth numbers in the text report.
    # We allow a small tolerance since formatting might vary (e.g. rounding).
    
    needed_values = {
        "c_path": "Total Effect (Anxiety -> Exam)",
        "a_path": "Path a (Anxiety -> Revise)",
        "b_path": "Path b (Revise -> Exam)",
        "c_prime_path": "Direct Effect (Anxiety -> Exam | Revise)",
        "indirect_effect": "Indirect Effect"
    }
    
    stats_score = 0
    max_stats_score = 70
    item_value = max_stats_score / len(needed_values) # 14 pts each
    
    # Helper to find value in text
    def find_value_in_text(target_val, text, tolerance=0.15):
        # Look for numbers in text
        numbers = re.findall(r"[-+]?\d*\.\d+|\d+", text)
        for num_str in numbers:
            try:
                val = float(num_str)
                if math.isclose(val, target_val, abs_tol=tolerance):
                    return True
            except ValueError:
                continue
        return False

    correct_items = 0
    for key, label in needed_values.items():
        target = ground_truth.get(key)
        if target is None:
            # Fallback if GT calculation failed in setup
            continue
            
        if find_value_in_text(target, report_text):
            stats_score += item_value
            correct_items += 1
            feedback.append(f"Found correct value for {label} ({target:.2f}).")
        else:
            feedback.append(f"Missing or incorrect value for {label} (Expected ~{target:.2f}).")
    
    score += int(stats_score)

    # Mediation Conclusion Check
    # Since partial mediation is the answer (Direct effect reduces but stays significant or just reduces),
    # usually we look for words like "partial", "mediation supported", etc.
    # But strictly checking text semantics is flaky without VLM. 
    # We'll stick to the numeric check for the main score.

    # Final Pass Determination
    # Pass if OMV exists, Report exists, and at least 3/5 statistical values are correct
    passed = omv_valid and report_exists and (correct_items >= 3)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }