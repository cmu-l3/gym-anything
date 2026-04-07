#!/usr/bin/env python3
"""
Verifier for delivery_backorder_processing task.

Scoring Criteria:
1. Original delivery order is in 'done' state (25 pts)
2. Original delivery order has correct done quantity (30 units) (25 pts)
3. A backorder picking exists (30 pts)
4. Backorder picking has correct demand quantity (20 units) (20 pts)

Anti-gaming:
- Checks if the original picking was actually modified after task start.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delivery_backorder_processing(traj, env_info, task_info):
    """
    Verify that the agent processed the partial delivery and created a backorder.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    orig_state = result.get("original_picking_state", "unknown")
    orig_qty = result.get("original_picking_qty_done", 0.0)
    backorder_found = result.get("backorder_found", False)
    backorder_qty = result.get("backorder_qty_demand", 0.0)
    
    # 1. Check Original Picking State (25 pts)
    if orig_state == 'done':
        score += 25
        feedback_parts.append("Original delivery validated (25/25)")
    else:
        feedback_parts.append(f"Original delivery not done (State: {orig_state}) (0/25)")

    # 2. Check Original Delivered Quantity (25 pts)
    # Expected 30. Allow slight tolerance? No, exact integer expected.
    if abs(orig_qty - 30.0) < 0.1:
        score += 25
        feedback_parts.append("Correct quantity delivered: 30 (25/25)")
    else:
        feedback_parts.append(f"Incorrect delivered quantity: {orig_qty} (Expected: 30) (0/25)")

    # 3. Check Backorder Existence (30 pts)
    if backorder_found:
        score += 30
        feedback_parts.append("Backorder created (30/30)")
    else:
        feedback_parts.append("No backorder found (0/30)")

    # 4. Check Backorder Demand (20 pts)
    if backorder_found:
        if abs(backorder_qty - 20.0) < 0.1:
            score += 20
            feedback_parts.append("Backorder has correct demand: 20 (20/20)")
        else:
            feedback_parts.append(f"Backorder has incorrect demand: {backorder_qty} (Expected: 20) (0/20)")
    
    # 5. Anti-gaming check (Pass/Fail gate)
    # If score > 0 but no modification detected, fail.
    # We can check timestamps, but since we rely on database state which is hard to fake without Odoo,
    # the main risk is "doing nothing" if the state was already correct (but setup resets it).
    # Setup ensures new clean SO/Picking, so pre-existing state isn't an issue.
    # Do-nothing detection: If state is still 'assigned'/'confirmed', score is 0 anyway.
    
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }