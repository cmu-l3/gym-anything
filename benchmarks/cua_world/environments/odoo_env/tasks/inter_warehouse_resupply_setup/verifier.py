#!/usr/bin/env python3
"""
Verifier for inter_warehouse_resupply_setup task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inter_warehouse_resupply_setup(traj, env_info, task_info):
    """
    Verifies the Odoo Inter-Warehouse Resupply task.
    """
    # 1. Retrieve result data from the container
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

    # 2. Score the task
    score = 0
    feedback = []

    # Criterion 1: Warehouse Created (20 pts)
    if result.get("warehouse_created"):
        score += 20
        feedback.append("Warehouse 'Downtown Pop-up' (POP) created.")
    else:
        feedback.append("Warehouse 'POP' not found.")

    # Criterion 2: Resupply Route Configured (20 pts)
    if result.get("resupply_route_configured"):
        score += 20
        feedback.append("Resupply route from San Francisco configured.")
    else:
        feedback.append("Resupply route NOT configured correctly (check 'Resupply from...' setting).")

    # Criterion 3: Reordering Rule (20 pts)
    if result.get("reordering_rule_correct"):
        score += 20
        feedback.append("Reordering rule (Min 10, Max 30) created correctly.")
    else:
        rule_details = result.get("details", {}).get("rule", "None")
        feedback.append(f"Reordering rule incorrect or missing. Found: {rule_details}")

    # Criterion 4: Transfer Created & Validated (20 pts)
    if result.get("transfer_validated"):
        score += 20
        feedback.append("Replenishment transfer generated and validated.")
    elif result.get("transfer_created"):
        score += 10
        feedback.append("Transfer generated but NOT validated (State is not 'Done').")
    else:
        feedback.append("No replenishment transfer found.")

    # Criterion 5: Final Stock Level (20 pts)
    if result.get("stock_correct"):
        score += 20
        feedback.append("Stock successfully replenished at POP.")
    else:
        qty = result.get("details", {}).get("final_qty", 0)
        feedback.append(f"Stock level insufficient (Found: {qty}, Expected: >=10).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }