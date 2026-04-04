#!/usr/bin/env python3
"""
Verifier for update_vaccine_inventory task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_vaccine_inventory(traj, env_info, task_info):
    """
    Verify the vaccine inventory was updated correctly.
    Target: Lot ADC-AUDIT-25 should have 12 units (started with 25).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_qty = metadata.get('expected_quantity', 12)
    initial_qty = metadata.get('initial_quantity', 25)
    target_lot = metadata.get('target_lot', 'ADC-AUDIT-25')

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Criteria
    score = 0
    feedback_parts = []
    
    # 1. Check if lot exists (Critical) - 20 pts
    lot_exists = result.get('lot_exists', False)
    if not lot_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Lot {target_lot} was deleted or not found.",
            "details": {"lot_found": False}
        }
    score += 20
    feedback_parts.append(f"Lot {target_lot} found")

    # 2. Check value update (Critical) - 50 pts
    final_unit = result.get('final_unit')
    
    # Handle possible None/Null
    if final_unit is None:
        final_unit = -1 # Sentinel for logic
    
    # Explicit conversion to int for comparison
    try:
        final_unit = int(final_unit)
    except (ValueError, TypeError):
        feedback_parts.append(f"Invalid unit value found: {final_unit}")
        final_unit = -999

    if final_unit == expected_qty:
        score += 50
        feedback_parts.append(f"Quantity correctly updated to {expected_qty}")
    else:
        feedback_parts.append(f"Incorrect quantity: {final_unit} (Expected: {expected_qty})")

    # 3. Anti-gaming / Do-nothing check (10 pts)
    # If final_unit == initial_unit (25), agent likely did nothing
    if final_unit != initial_qty:
        score += 10
        feedback_parts.append("Value was modified from initial state")
    else:
        feedback_parts.append("Value unchanged from initial state (Did nothing?)")

    # 4. Check active status (20 pts)
    # Should still be active (1), not disabled
    active = result.get('active')
    if str(active) == "1":
        score += 20
        feedback_parts.append("Lot remains active")
    else:
        feedback_parts.append(f"Lot is inactive (status: {active})")

    # Final Pass check
    # Need at least 70 points (Meaning they must have updated the quantity correctly)
    passed = (score >= 70) and (final_unit == expected_qty)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "final_unit": final_unit,
            "expected": expected_qty,
            "lot_exists": lot_exists
        }
    }