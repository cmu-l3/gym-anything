#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_internal_transfer(traj, env_info, task_info):
    """
    Verifies the inventory internal transfer task.
    
    Scoring:
    - Transfer exists: 10 pts
    - Source/Dest Correct: 20 pts
    - Reference Correct: 10 pts
    - Products/Qty Correct: 30 pts
    - Validated (Done state): 20 pts
    - Stock Levels Updated: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Check for setup error
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": "Setup failed or missing."}

    score = 0
    feedback = []

    # 1. Transfer Found (10)
    if result.get("transfer_found"):
        score += 10
        feedback.append("Transfer record found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No internal transfer found matching criteria."}

    # 2. Locations (20)
    if result.get("source_loc_correct") and result.get("dest_loc_correct"):
        score += 20
        feedback.append("Source and Destination locations correct.")
    else:
        feedback.append("Incorrect locations.")

    # 3. Reference (10)
    if result.get("reference_match"):
        score += 10
        feedback.append("Reference code matches.")
    else:
        feedback.append("Reference code missing or incorrect.")

    # 4. Products/Qty (30)
    if result.get("products_correct"):
        score += 30
        feedback.append("Products and quantities correct.")
    else:
        feedback.append("Incorrect products or quantities in transfer.")

    # 5. State (20)
    if result.get("transfer_state") == "done":
        score += 20
        feedback.append("Transfer validated (Done).")
    else:
        feedback.append(f"Transfer not validated (State: {result.get('transfer_state')}).")

    # 6. Stock Levels (10)
    if result.get("stock_levels_correct"):
        score += 10
        feedback.append("Final stock levels verified correct.")
    else:
        feedback.append("Stock levels not updated correctly.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }