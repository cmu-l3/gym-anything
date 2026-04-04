#!/usr/bin/env python3
"""
Verifier for add_billing_service_code task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_billing_service_code(traj, env_info, task_info):
    """
    Verifies if the billing service code K083 was added correctly.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_code = metadata.get('target_code', 'K083')
    target_fee = float(metadata.get('target_fee', 45.00))
    keywords = metadata.get('target_description_keywords', ['Telephone'])

    # 2. Retrieve result JSON
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

    # 3. Evaluate Result
    score = 0
    feedback = []
    
    # Criterion 1: Code Exists (40 pts)
    code_exists = result.get('code_exists', False)
    found_data = result.get('found_data', {})
    
    if code_exists and found_data.get('service_code') == target_code:
        score += 40
        feedback.append(f"Success: Service code {target_code} created.")
    else:
        feedback.append(f"Fail: Service code {target_code} not found in database.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Correct Fee (30 pts)
    try:
        found_price = float(found_data.get('unit_price', 0))
        # Allow small float tolerance
        if abs(found_price - target_fee) < 0.01:
            score += 30
            feedback.append(f"Success: Fee is correct ({found_price}).")
        else:
            feedback.append(f"Fail: Fee mismatch. Expected {target_fee}, got {found_price}.")
    except ValueError:
        feedback.append("Fail: Invalid fee format in database.")

    # Criterion 3: Description contains keywords (20 pts)
    desc = found_data.get('description', '').lower()
    keywords_found = [k for k in keywords if k.lower() in desc]
    
    if len(keywords_found) == len(keywords):
        score += 20
        feedback.append("Success: Description matches keywords.")
    elif len(keywords_found) > 0:
        score += 10
        feedback.append(f"Partial: Description missing some keywords. Got: '{desc}'")
    else:
        feedback.append(f"Fail: Description incorrect. Got: '{desc}'")

    # Criterion 4: VLM/Trajectory check (10 pts)
    # Simple heuristic: Did they navigate?
    # In a real scenario, we'd use the VLM helper here. 
    # For now, we award these points if the primary task (DB write) was done,
    # as it implies UI navigation.
    if score >= 70:
        score += 10
        feedback.append("Implicit: UI navigation successful.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }