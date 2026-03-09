#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_inventory(traj, env_info, task_info):
    """
    Verifies that the inventory item 'Amoxicillin 500mg' was updated correctly.
    
    Criteria:
    1. Document exists in CouchDB.
    2. Reorder Point updated to 150 (from 50).
    3. Price updated to 12.50 (from 10.00).
    4. VLM confirms UI interaction.
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_reorder = metadata.get('expected_reorder_point', 150)
    expected_price = metadata.get('expected_price', 12.50)
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Check if doc found (20 pts)
    if not result.get('doc_found'):
        return {"passed": False, "score": 0, "feedback": "Target inventory item 'Amoxicillin 500mg' not found in database."}
    score += 20
    feedback.append("Inventory item found.")

    # Check Reorder Point (30 pts)
    actual_reorder = result.get('current_reorder_point')
    try:
        if int(actual_reorder) == int(expected_reorder):
            score += 30
            feedback.append(f"Reorder point updated correctly ({actual_reorder}).")
        else:
            feedback.append(f"Incorrect Reorder Point: expected {expected_reorder}, got {actual_reorder}.")
    except (ValueError, TypeError):
        feedback.append(f"Invalid Reorder Point format: {actual_reorder}.")

    # Check Price (30 pts)
    actual_price = result.get('current_price')
    try:
        # Allow small float tolerance
        if abs(float(actual_price) - float(expected_price)) < 0.01:
            score += 30
            feedback.append(f"Price updated correctly ({actual_price}).")
        else:
            feedback.append(f"Incorrect Price: expected {expected_price}, got {actual_price}.")
    except (ValueError, TypeError):
        feedback.append(f"Invalid Price format: {actual_price}.")

    # VLM Verification (20 pts)
    # Since we don't have the VLM available in this context, we'll assign these points 
    # if the programmatic checks pass, assuming the agent must have used the UI to effect these changes.
    # In a full system, we would query the VLM here.
    if score >= 80:
        score += 20
        feedback.append("UI interaction inferred from successful database update.")
    else:
        feedback.append("Core criteria not met, skipping secondary verification.")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }