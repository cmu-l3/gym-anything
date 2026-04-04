#!/usr/bin/env python3
"""
Verifier for snapshot_search_results task.

Scoring:
- 20 pts: Collection "Theoretical Foundations" exists
- 10 pts: It is a static collection, NOT a Saved Search
- 40 pts: Recall (Contains all correct papers)
- 30 pts: Precision (Does not contain incorrect papers)
"""

import json
import os
import tempfile

def verify_snapshot_search_results(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load result JSON
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

    # Scoring variables
    score = 0
    feedback = []
    
    # 1. Check existence (20 pts)
    if result.get("collection_exists"):
        score += 20
        feedback.append("Collection 'Theoretical Foundations' created.")
    else:
        feedback.append("Collection 'Theoretical Foundations' NOT found.")
        # If collection doesn't exist, we can't score contents, but check if they made a saved search
        if result.get("is_saved_search"):
            feedback.append("Found a Saved Search instead of a Collection (wrong type).")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 2. Check type (10 pts)
    if result.get("is_saved_search"):
        feedback.append("Error: Created a Saved Search instead of a static Collection.")
    else:
        score += 10
        feedback.append("Correctly created a static collection.")

    # 3. Check Contents (70 pts split between precision and recall)
    items_in_col = set(result.get("items_in_collection", []))
    ground_truth = set(result.get("ground_truth_items", []))
    
    if not ground_truth:
        return {"passed": False, "score": 0, "feedback": "Error: Setup failed, no ground truth items found in DB."}

    # Calculate overlaps
    true_positives = items_in_col.intersection(ground_truth)
    false_positives = items_in_col - ground_truth
    false_negatives = ground_truth - items_in_col
    
    # Recall Score (40 pts)
    # Fraction of required items that were actually added
    if len(ground_truth) > 0:
        recall = len(true_positives) / len(ground_truth)
        recall_pts = int(recall * 40)
        score += recall_pts
        feedback.append(f"Found {len(true_positives)}/{len(ground_truth)} required papers (+{recall_pts} pts).")
        if false_negatives:
            feedback.append(f"Missing: {list(false_negatives)[:2]}...")
    
    # Precision Score (30 pts)
    # Penalize for extra items. 
    if len(items_in_col) > 0:
        # Simple linear penalty: 30 pts max, subtract proportional to error rate?
        # Let's do: Precision = TP / (TP + FP)
        precision = len(true_positives) / len(items_in_col)
        precision_pts = int(precision * 30)
        score += precision_pts
        feedback.append(f"Precision: {int(precision*100)}% (+{precision_pts} pts).")
        if false_positives:
            feedback.append(f"Incorrectly added: {list(false_positives)[:2]}...")
    elif len(items_in_col) == 0:
        feedback.append("Collection is empty.")
        # 0 points for precision if empty

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }