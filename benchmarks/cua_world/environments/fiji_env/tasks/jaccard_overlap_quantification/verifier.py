#!/usr/bin/env python3
"""
Verifier for Jaccard Overlap Quantification task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_jaccard_overlap(traj, env_info, task_info):
    """
    Verifies the Jaccard calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Unpack data
    files = result.get("files_found", {})
    gt = result.get("ground_truth", {})
    agent_reported = result.get("agent_reported", {})
    mask_acc = result.get("mask_accuracy", {})

    # 1. File Existence (20 pts)
    # intersection, union, csv
    file_score = 0
    if files.get("intersection_mask.tif") and files.get("intersection_mask.tif_new"):
        file_score += 7
    if files.get("union_mask.tif") and files.get("union_mask.tif_new"):
        file_score += 7
    if files.get("results.csv") and files.get("results.csv_new"):
        file_score += 6
    
    score += file_score
    if file_score == 20:
        feedback.append("All output files created successfully.")
    else:
        feedback.append(f"Missing or old output files (Score: {file_score}/20).")

    # 2. Mask Accuracy (50 pts)
    # Check if the saved masks match the programmatic GT
    int_acc = mask_acc.get("intersection", 0.0)
    union_acc = mask_acc.get("union", 0.0)
    
    # Threshold for mask correctness (allow slight differences due to Fiji versioning/implementations)
    THRESHOLD = 0.95 
    
    if int_acc > THRESHOLD:
        score += 25
        feedback.append("Intersection mask matches ground truth.")
    elif int_acc > 0.5:
        score += 10
        feedback.append(f"Intersection mask has poor overlap ({int_acc:.2f}).")
    else:
        feedback.append("Intersection mask incorrect or missing.")

    if union_acc > THRESHOLD:
        score += 25
        feedback.append("Union mask matches ground truth.")
    elif union_acc > 0.5:
        score += 10
        feedback.append(f"Union mask has poor overlap ({union_acc:.2f}).")
    else:
        feedback.append("Union mask incorrect or missing.")

    # 3. Reported Jaccard Value (30 pts)
    reported_j = agent_reported.get("jaccard")
    gt_j = gt.get("jaccard")
    
    if reported_j is not None and gt_j is not None:
        diff = abs(reported_j - gt_j)
        if diff < 0.05:
            score += 30
            feedback.append(f"Reported Jaccard index ({reported_j:.3f}) matches ground truth ({gt_j:.3f}).")
        elif diff < 0.1:
            score += 15
            feedback.append(f"Reported Jaccard index ({reported_j:.3f}) is close to ground truth ({gt_j:.3f}).")
        else:
            feedback.append(f"Reported Jaccard index ({reported_j:.3f}) incorrect (Expected: {gt_j:.3f}).")
    else:
        feedback.append("Jaccard index not found in CSV or could not calculate ground truth.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }