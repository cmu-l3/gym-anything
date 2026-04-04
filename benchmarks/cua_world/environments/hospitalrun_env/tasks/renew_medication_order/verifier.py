#!/usr/bin/env python3
"""
Verifier for renew_medication_order task.
"""

import json
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_renew_medication(traj, env_info, task_info):
    """
    Verifies that a new medication order was created with the correct historical details.
    
    Criteria:
    1. A new medication order exists for Martha Kent (not the old one).
    2. Drug name contains "Amlodipine" (case insensitive).
    3. Dosage matches "5mg" (normalized check).
    4. Status is Active/Requested.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_drug = metadata.get('hidden_drug', 'Amlodipine').lower()
    expected_dosage = metadata.get('hidden_dosage', '5mg').lower().replace(" ", "") # normalize "5 mg" -> "5mg"
    
    # Copy result file
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # 2. Analyze Results
    new_orders = result_data.get('new_orders', [])
    
    if isinstance(new_orders, dict) and 'error' in new_orders:
        return {"passed": False, "score": 0, "feedback": f"Error querying database: {new_orders['error']}"}
        
    if not new_orders:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new active medication orders found for Martha Kent. Did you save the order?"
        }

    # Check the best matching order
    best_match_score = 0
    feedback_details = []
    passed = False
    
    for order in new_orders:
        current_score = 0
        current_feedback = []
        
        # 1. Check Drug Name (Critical)
        drug = order.get('medication', '').lower()
        if expected_drug in drug:
            current_score += 40
            current_feedback.append(f"Correct Drug ({order.get('medication')})")
        else:
            current_feedback.append(f"Wrong Drug: {order.get('medication')}")

        # 2. Check Dosage (Critical - this was the hidden info)
        dosage = str(order.get('dosage', '')).lower().replace(" ", "")
        if expected_dosage in dosage:
            current_score += 40
            current_feedback.append(f"Correct Dosage ({order.get('dosage')})")
        else:
            current_feedback.append(f"Wrong Dosage: {order.get('dosage')} (Expected: {expected_dosage})")
            
        # 3. Check Frequency (Bonus/Confirmation)
        freq = str(order.get('frequency', '')).lower()
        if 'daily' in freq or 'qd' in freq or 'once' in freq:
            current_score += 10
            current_feedback.append("Correct Frequency")

        # 4. Check Status
        status = order.get('status', '').lower()
        if status in ['active', 'requested', 'ordered']:
            current_score += 10
            current_feedback.append("Correct Status")
            
        # Evaluate
        if current_score > best_match_score:
            best_match_score = current_score
            feedback_details = current_feedback

    # Final scoring logic
    # Must get Drug AND Dosage right to pass (80 pts threshold)
    if best_match_score >= 80:
        passed = True
        final_feedback = "Success: " + ", ".join(feedback_details)
    else:
        passed = False
        final_feedback = "Failed: " + ", ".join(feedback_details)
        if best_match_score == 0:
            final_feedback = "Failed: Created an order but details (Drug/Dosage) did not match expectations."

    return {
        "passed": passed,
        "score": best_match_score,
        "feedback": final_feedback
    }