#!/usr/bin/env python3
"""
Verifier for collect_documents_for_legal_hold task.
Checks if the 'Legal Hold - Acme' collection exists and contains exactly the correct documents.
"""

import json
import os
import sys

def verify_legal_hold_collection(traj, env_info, task_info):
    """
    Verify the Legal Hold collection task.
    
    Criteria:
    1. Collection 'Legal Hold - Acme' exists (20 pts)
    2. 'Acme Service Agreement' is in collection (25 pts)
    3. 'Acme NDA Agreement' is in collection (25 pts)
    4. No incorrect documents (precision) (30 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result from container
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # 2. Analyze Results
    score = 0
    feedback = []
    
    # Criterion 1: Collection Exists (20 pts)
    if result_data.get("collection_found"):
        score += 20
        feedback.append("Collection 'Legal Hold - Acme' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Collection 'Legal Hold - Acme' was not found."}

    # Analyze Members
    members = result_data.get("members", [])
    member_titles = [m.get("title", "") for m in members]
    
    # Expected Targets
    target_1 = "Acme Service Agreement"
    target_2 = "Acme NDA Agreement"
    
    # Distractors
    distractor_1 = "Acme Invoice" # Prefix match
    distractor_2 = "Beta Service Agreement"
    
    # Criterion 2: Target 1 (25 pts)
    if target_1 in member_titles:
        score += 25
        feedback.append(f"Correctly added '{target_1}'.")
    else:
        feedback.append(f"Missing required document '{target_1}'.")

    # Criterion 3: Target 2 (25 pts)
    if target_2 in member_titles:
        score += 25
        feedback.append(f"Correctly added '{target_2}'.")
    else:
        feedback.append(f"Missing required document '{target_2}'.")

    # Criterion 4: Precision (30 pts)
    # Deduct for unwanted files
    unwanted_found = []
    for title in member_titles:
        if title != target_1 and title != target_2:
            unwanted_found.append(title)
    
    if not unwanted_found:
        score += 30
        feedback.append("Precision bonus: Only correct documents included.")
    else:
        # Partial credit if only few errors? 
        # Let's say -10 pts per error, min 0 for this section
        penalty = len(unwanted_found) * 10
        precision_score = max(0, 30 - penalty)
        score += precision_score
        feedback.append(f"Precision penalty: Included {len(unwanted_found)} incorrect document(s) ({', '.join(unwanted_found)}).")

    # 3. Final Assessment
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }