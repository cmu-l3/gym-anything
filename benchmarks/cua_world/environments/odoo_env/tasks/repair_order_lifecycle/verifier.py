#!/usr/bin/env python3
"""
Verifier for repair_order_lifecycle task.

Scoring (100 points):
- Repair Order Created & Found: 10 pts
- Repair State is 'done': 20 pts
- Correct Part (Battery) included: 20 pts
- Correct Labor included (Qty >= 2.0): 20 pts
- Invoice Created: 15 pts
- Invoice Posted: 15 pts

Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_repair_order_lifecycle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env('/tmp/repair_order_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"System Error: {result['error']}"}

    score = 0
    feedback = []

    # 1. Repair Found (10)
    if result.get('repair_found'):
        score += 10
        feedback.append("Repair order found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No repair order found for 'Constructors Inc'."}

    # 2. Repair State (20)
    state = result.get('repair_state', '')
    if state == 'done':
        score += 20
        feedback.append("Repair order is marked as Done.")
    else:
        feedback.append(f"Repair order state is '{state}' (expected 'done').")

    # 3. Parts (20)
    if result.get('parts_found'):
        score += 20
        feedback.append("Replacement battery found in order.")
    else:
        feedback.append("High-Capacity Battery not found in repair lines.")

    # 4. Labor (20)
    if result.get('labor_found'):
        qty = result.get('labor_qty', 0)
        if qty >= 2.0:
            score += 20
            feedback.append(f"Labor correctly charged ({qty} hours).")
        else:
            score += 10
            feedback.append(f"Labor found but quantity {qty} is less than 2.0.")
    else:
        feedback.append("Repair Labor service not found in order.")

    # 5. Invoice Created (15)
    if result.get('invoice_created'):
        score += 15
        feedback.append("Invoice generated.")
    else:
        feedback.append("No invoice generated for repair.")

    # 6. Invoice Posted (15)
    inv_state = result.get('invoice_state', '')
    if inv_state == 'posted':
        score += 15
        feedback.append("Invoice is posted.")
    elif result.get('invoice_created'):
        feedback.append(f"Invoice in state '{inv_state}' (expected 'posted').")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }