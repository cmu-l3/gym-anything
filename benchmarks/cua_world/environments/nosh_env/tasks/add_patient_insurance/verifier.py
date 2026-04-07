#!/usr/bin/env python3
"""
Verifier for add_patient_insurance task.

Checks if the agent correctly added the primary insurance information
for patient Maria Gonzalez in the NOSH EHR database.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_patient_insurance(traj, env_info, task_info):
    """
    Verify insurance data entry in database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_plan = metadata.get('expected_plan_name', 'Blue Cross Blue Shield')
    expected_id = metadata.get('expected_id', 'BCB993847210')
    expected_group = metadata.get('expected_group', 'GRP-55128')
    expected_copay = metadata.get('expected_copay', '30')
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check 1: Record exists (15 pts)
    record_exists = result.get('record_exists', False)
    if not record_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No insurance record found for the patient."
        }
    
    score += 15
    feedback_parts.append("Insurance record created")
    
    # Check 2: Anti-gaming (New record created) (10 pts)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    if current_count > initial_count:
        score += 10
        feedback_parts.append("New record confirmed")
    else:
        feedback_parts.append("Warning: Insurance count did not increase")

    # Get data
    data = result.get('insurance_data', {})
    
    # Check 3: Plan Name (20 pts)
    # Flexible match for "Blue Cross" or "BCBS"
    plan_name = data.get('plan_name', '').strip()
    if 'blue cross' in plan_name.lower() or 'bcbs' in plan_name.lower():
        score += 20
        feedback_parts.append(f"Plan name correct ('{plan_name}')")
    else:
        feedback_parts.append(f"Plan name mismatch (expected '{expected_plan}', got '{plan_name}')")

    # Check 4: ID Number (20 pts)
    # Exact or close match
    id_num = data.get('id_number', '').strip()
    if id_num == expected_id:
        score += 20
        feedback_parts.append("ID Number exact match")
    elif expected_id in id_num:
        score += 15 # Partial credit if extra chars
        feedback_parts.append("ID Number partial match")
    else:
        feedback_parts.append(f"ID Number mismatch (expected '{expected_id}', got '{id_num}')")

    # Check 5: Group Number (15 pts)
    group_num = data.get('group_number', '').strip()
    if '55128' in group_num:
        score += 15
        feedback_parts.append(f"Group number correct ('{group_num}')")
    else:
        feedback_parts.append(f"Group number mismatch (expected '{expected_group}', got '{group_num}')")

    # Check 6: Insurance Order (10 pts)
    ins_order = str(data.get('order', '')).lower()
    if 'primary' in ins_order or '1' in ins_order:
        score += 10
        feedback_parts.append("Marked as Primary")
    else:
        feedback_parts.append(f"Insurance order incorrect ('{ins_order}')")

    # Check 7: Copay (10 pts)
    copay = str(data.get('copay', '')).replace('$', '').strip()
    # Handle "30.00" vs "30"
    if copay.startswith('30'):
        score += 10
        feedback_parts.append("Copay correct")
    else:
        feedback_parts.append(f"Copay mismatch (expected '{expected_copay}', got '{copay}')")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }