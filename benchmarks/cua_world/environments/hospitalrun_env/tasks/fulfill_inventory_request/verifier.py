#!/usr/bin/env python3
"""
Verifier for fulfill_inventory_request task.

Verifies that:
1. The inventory request status transitioned to 'Fulfilled'.
2. The inventory item quantity decreased by the requested amount (50).
3. Visual navigation steps were performed (Inventory -> Requests -> Fulfill).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fulfill_inventory_request(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_status = metadata.get('expected_status', 'Fulfilled')
    expected_final_qty = metadata.get('expected_final_quantity', 450)
    initial_qty = metadata.get('initial_quantity', 500)
    
    # 1. Load Programmatic Results
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

    # --- Criterion 1: Request Status (35 pts) ---
    actual_status = result.get('request_status', 'Unknown')
    rev_changed = result.get('rev_changed', False)
    
    if actual_status.lower() == expected_status.lower():
        score += 35
        feedback.append("Success: Request status is 'Fulfilled'.")
    else:
        feedback.append(f"Fail: Request status is '{actual_status}' (expected '{expected_status}').")

    # --- Criterion 2: Inventory Quantity (20 pts) ---
    final_qty = result.get('final_quantity', -1)
    
    if final_qty == expected_final_qty:
        score += 20
        feedback.append(f"Success: Inventory quantity updated correctly to {final_qty}.")
    elif final_qty < initial_qty:
        # Partial credit if it decreased but maybe not exactly (e.g. user changed fulfilled amount)
        score += 10
        feedback.append(f"Partial: Inventory quantity decreased to {final_qty} (expected {expected_final_qty}).")
    else:
        feedback.append(f"Fail: Inventory quantity is {final_qty} (started at {initial_qty}).")

    # --- Criterion 3: Anti-Gaming / Database Modification (10 pts) ---
    if rev_changed:
        score += 10
        feedback.append("System: Database record modified during task.")
    else:
        feedback.append("System: No changes detected in request record.")

    # --- Criterion 4: VLM Trajectory Verification (35 pts) ---
    # We define "passing" logic separate from score to require VLM + Status
    
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with HospitalRun.
    The goal is to fulfill an inventory request.
    
    Look for:
    1. Navigation to the "Inventory" section (sidebar or header).
    2. A list of requests or a table showing "Sterile Gauze".
    3. A "Fulfill" button being clicked or a fulfillment modal/popup.
    4. A success message or status change.

    Return JSON:
    {
        "inventory_visited": true/false,
        "request_list_seen": true/false,
        "fulfill_action_attempted": true/false,
        "explanation": "brief description"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {}) if vlm_result else {}
    
    if vlm_data.get('inventory_visited', False):
        score += 15
        feedback.append("VLM: Inventory section visited.")
    
    if vlm_data.get('request_list_seen', False):
        score += 10
        feedback.append("VLM: Request list viewed.")
        
    if vlm_data.get('fulfill_action_attempted', False):
        score += 10
        feedback.append("VLM: Fulfillment action observed.")

    # Calculate Final Pass State
    # Must have correct status AND reasonable score
    passed = (actual_status.lower() == expected_status.lower()) and (score >= 55)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }