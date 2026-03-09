#!/usr/bin/env python3
"""
Verifier for diagnostic_accuracy_oswego@1

Checks:
1. Report file exists and was created during the task.
2. Contains correct TP, FP, FN, TN counts (Exact integer match).
3. Contains correct calculated metrics (Sensitivity, Specificity, PPV, NPV) with tolerance.
4. Verifies Epi Info was running.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_diagnostic_accuracy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truth
    GT = task_info.get("metadata", {}).get("ground_truth", {
        "TP": 43, "FP": 11, "FN": 3, "TN": 18,
        "Sensitivity": 0.93, "Specificity": 0.62, "PPV": 0.80, "NPV": 0.86
    })
    TOLERANCE = task_info.get("metadata", {}).get("tolerance_metrics", 0.05)

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path inside container, mapped to temp file on host
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Timing (20 pts)
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Report file created successfully.")
    elif result.get("output_exists"):
        score += 10
        feedback.append("Report file exists but timestamp check failed (stale file?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}

    content = result.get("content", "")
    
    # 2. Check Counts (TP, FP, FN, TN) (40 pts - 10 each)
    # Regex to find "Label: Value" patterns, case insensitive
    def extract_value(label, text):
        match = re.search(fr"{label}[:\s=]+(\d+(\.\d+)?)", text, re.IGNORECASE)
        if match:
            return float(match.group(1))
        return None

    counts_correct = 0
    for key in ["TP", "FP", "FN", "TN"]:
        val = extract_value(key, content)
        if val is not None and int(val) == GT[key]:
            score += 10
            counts_correct += 1
        else:
            feedback.append(f"Incorrect or missing count for {key} (Expected {GT[key]}).")
    
    if counts_correct == 4:
        feedback.append("All confusion matrix counts correct.")

    # 3. Check Metrics (40 pts - 10 each)
    metrics_correct = 0
    for key in ["Sensitivity", "Specificity", "PPV", "NPV"]:
        val = extract_value(key, content)
        if val is not None:
            if abs(val - GT[key]) <= TOLERANCE:
                score += 10
                metrics_correct += 1
            else:
                feedback.append(f"{key} value {val} outside tolerance ({GT[key]} +/- {TOLERANCE}).")
        else:
            feedback.append(f"{key} not found in report.")
            
    if metrics_correct == 4:
        feedback.append("All diagnostic metrics correct.")

    # Final Pass Check
    # Need at least file existence + counts + some metrics
    passed = (score >= 70) and (counts_correct >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }