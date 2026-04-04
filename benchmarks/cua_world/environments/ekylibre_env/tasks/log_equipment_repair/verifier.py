#!/usr/bin/env python3
"""
Verifier for log_equipment_repair@1

Verifies that a repair intervention was logged in Ekylibre with:
- Correct nature (Repair/Maintenance)
- Correct target (Tractor/Equipment)
- Correct cost (245.50 EUR)
- Correct description keywords
- Created during the task session (anti-gaming)
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_equipment_repair(traj, env_info, task_info):
    """
    Verify the equipment repair logging task.
    """
    # 1. Setup - Load data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    found = result.get('intervention_found', False)
    intervention = result.get('intervention', {})
    
    nature = str(intervention.get('nature', '')).lower()
    description = str(intervention.get('description', '')).lower()
    amount_str = str(intervention.get('amount', '0'))
    target_name = str(intervention.get('target_name', '')).lower()
    target_nature = str(intervention.get('target_nature', '')).lower()
    
    # Clean amount string (handle potential currency symbols or commas)
    try:
        amount_val = float(amount_str.replace(',', '.').replace('€', '').strip() or 0)
    except ValueError:
        amount_val = 0.0

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: Intervention Created (30 pts)
    if found and intervention.get('id'):
        score += 30
        feedback.append("Intervention record created.")
    else:
        # Check if count increased even if query failed to pick specific one
        initial = result.get('counts', {}).get('initial', 0)
        final = result.get('counts', {}).get('final', 0)
        if final > initial:
            score += 10
            feedback.append("Intervention count increased, but details verify failed.")
        else:
            return {"passed": False, "score": 0, "feedback": "No intervention created during task."}

    # Criterion 2: Correct Nature (15 pts)
    # Expected: repair, maintenance, réparation, entretien
    nature_keywords = metadata.get('expected_nature_keywords', ["repair", "réparation", "maintenance", "entretien"])
    if any(k in nature for k in nature_keywords):
        score += 15
        feedback.append(f"Correct nature: '{nature}'.")
    else:
        feedback.append(f"Incorrect nature: '{nature}' (expected Repair/Maintenance).")

    # Criterion 3: Linked to Equipment/Tractor (20 pts)
    # Check target name or target nature for tractor keywords
    target_keywords = metadata.get('target_equipment_keywords', ["tracteur", "tractor", "massey", "fendt", "deere"])
    if any(k in target_name for k in target_keywords) or any(k in target_nature for k in target_keywords):
        score += 20
        feedback.append(f"Correct target equipment: '{target_name}'.")
    else:
        feedback.append(f"Target does not appear to be a tractor: '{target_name}' (Type: {target_nature}).")

    # Criterion 4: Correct Cost (20 pts)
    expected_cost = metadata.get('expected_cost', 245.50)
    tolerance = 1.0 # Allow +/- 1 EUR
    if abs(amount_val - expected_cost) <= tolerance:
        score += 20
        feedback.append(f"Correct cost: {amount_val} EUR.")
    else:
        feedback.append(f"Incorrect cost: {amount_val} EUR (expected {expected_cost}).")

    # Criterion 5: Description Content (10 pts)
    desc_keywords = metadata.get('expected_description_keywords', ["rétroviseur", "mirror", "flexible", "hose"])
    matched_keywords = [k for k in desc_keywords if k in description]
    if len(matched_keywords) >= 1:
        score += 10
        feedback.append("Description contains required details.")
    else:
        feedback.append(f"Description missing details. Found: '{description}'")

    # Criterion 6: Anti-Gaming / Timestamp (5 pts)
    # If 'found' is true, our SQL query already filtered by timestamp >= start_time
    if found:
        score += 5
        feedback.append("Timestamp verified.")

    # 4. Final Result
    passed = (score >= 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "intervention_id": intervention.get('id'),
            "target": target_name,
            "amount": amount_val
        }
    }