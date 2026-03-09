#!/usr/bin/env python3
"""
Verifier for Bulk Dispatch Assignment Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_dispatch(traj, env_info, task_info):
    """
    Verifies that pilots were correctly assigned to flight plans based on the CSV roster.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # 1. Retrieve Agent Results
    agent_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", agent_result_file.name)
        with open(agent_result_file.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(agent_result_file.name):
            os.unlink(agent_result_file.name)

    # 2. Retrieve Ground Truth
    # Since ground truth is generated inside the container during setup, 
    # we need to copy it out as well to compare.
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/var/lib/aerobridge/roster_ground_truth.json", gt_file.name)
        with open(gt_file.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {str(e)}"}
    finally:
        if os.path.exists(gt_file.name):
            os.unlink(gt_file.name)

    # 3. Score the Assignments
    assignments = agent_data.get("assignments", {})
    
    total_items = len(ground_truth)
    if total_items == 0:
        return {"passed": False, "score": 0, "feedback": "Setup error: No ground truth items found."}

    correct_count = 0
    feedback_details = []

    for fp_id, expected in ground_truth.items():
        actual = assignments.get(fp_id, {})
        status = actual.get("status")
        
        if status == "assigned":
            # Check if email matches (using email is safer than ID generally, but we have both)
            actual_email = actual.get("assigned_person_email", "").lower()
            expected_email = expected.get("expected_email", "").lower()
            
            if actual_email == expected_email:
                correct_count += 1
                feedback_details.append(f"FP {fp_id}: Correctly assigned to {actual_email}")
            else:
                feedback_details.append(f"FP {fp_id}: Incorrect assignment. Expected {expected_email}, got {actual_email}")
        elif status == "unassigned":
            feedback_details.append(f"FP {fp_id}: Skipped / Unassigned")
        else:
            feedback_details.append(f"FP {fp_id}: Error or Missing ({status})")

    # Scoring logic
    score = (correct_count / total_items) * 100
    score = round(score)
    
    passed = score >= 80  # Threshold from task description

    feedback_str = f"Score: {score}/100\n"
    feedback_str += f"Correct Assignments: {correct_count}/{total_items}\n"
    feedback_str += "\n".join(feedback_details[:5]) # Show first 5 details
    if len(feedback_details) > 5:
        feedback_str += "\n..."

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }