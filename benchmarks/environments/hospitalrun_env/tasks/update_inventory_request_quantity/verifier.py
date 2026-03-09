#!/usr/bin/env python3
"""
Verifier for update_inventory_request_quantity task.

Criteria:
1. Document Verification:
   - The specific inventory request document (inv_req_masks_001) must still exist.
   - Quantity must be 500 (target).
   - Status must still be 'Requested' (not Fulfilled/Cancelled).
   - Inventory Item link must be preserved.

2. Anti-Gaming:
   - The document's revision (_rev) must be different from the initial revision
     captured during setup. This proves the agent actually saved a change.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_inventory_request(traj, env_info, task_info):
    # 1. Setup - Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    doc_exists = result.get("doc_exists", False)
    current_rev = result.get("current_rev", "")
    initial_rev = result.get("initial_rev", "")
    quantity = result.get("quantity")
    status = result.get("status", "")
    item_id = result.get("inventory_item_id", "")
    
    metadata = task_info.get("metadata", {})
    target_quantity = metadata.get("target_quantity", 500)
    expected_status = metadata.get("expected_status", "Requested")

    # 3. Score Calculation
    score = 0
    feedback = []

    # Criterion A: Document Exists (10 pts)
    if doc_exists:
        score += 10
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The inventory request document was deleted or not found."
        }

    # Criterion B: Modification Detected (Anti-Gaming) (30 pts)
    # The _rev must have changed, indicating a save operation occurred.
    if current_rev and current_rev != initial_rev:
        score += 30
        feedback.append("Document modification detected.")
    else:
        feedback.append("No changes were saved to the document (revision ID unchanged).")

    # Criterion C: Quantity Update (40 pts)
    # Allow string or int comparison
    try:
        qty_val = float(quantity)
        target_val = float(target_quantity)
        if qty_val == target_val:
            score += 40
            feedback.append(f"Quantity correctly updated to {target_quantity}.")
        else:
            feedback.append(f"Incorrect quantity: {qty_val} (expected {target_val}).")
    except (TypeError, ValueError):
        feedback.append(f"Invalid quantity value: {quantity}")

    # Criterion D: Integrity Check (20 pts)
    # Status should remain 'Requested' and Item link preserved
    integrity_score = 0
    if status == expected_status:
        integrity_score += 10
    else:
        feedback.append(f"Status changed unexpectedly to '{status}'.")
        
    # Check item link (simple check that it's not empty/null)
    if item_id and "inv_item_masks" in item_id:
        integrity_score += 10
    else:
        feedback.append("Inventory item link appears broken or changed.")
    
    score += integrity_score

    # 4. Final Result
    passed = score >= 85  # rigorous pass threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }