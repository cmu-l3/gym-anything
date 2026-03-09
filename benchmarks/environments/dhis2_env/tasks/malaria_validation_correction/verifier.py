#!/usr/bin/env python3
"""
Verifier for malaria_validation_correction task.

Scoring (100 points total):
1. Validation Rule Created (30 pts): Rule with correct name exists.
2. Rule Created Recently (10 pts): Created during the task.
3. Rule Logic (20 pts): 'less_than_or_equal' or 'less_than' operator used.
4. Data Corrected (Logic) (20 pts): Positive value <= Tested value.
5. Data Updated Recently (20 pts): The data value was modified during the task.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_malaria_validation_correction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/malaria_validation_correction_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    # 1. Validation Rule Created (30 pts)
    rule_exists = result.get('rule_exists', False)
    if rule_exists:
        score += 30
        feedback_parts.append("Validation Rule created (+30)")
    else:
        feedback_parts.append("Validation Rule NOT found")

    # 2. Rule Created Recently (10 pts)
    if result.get('rule_created_after_start', False):
        score += 10
        feedback_parts.append("Rule created during task (+10)")
    else:
        if rule_exists:
            feedback_parts.append("Rule predates task start (no points)")

    # 3. Rule Logic (20 pts)
    # DHIS2 operator strings: equal_to, not_equal_to, greater_than, greater_than_or_equal_to, less_than, less_than_or_equal_to
    # We want less_than or less_than_or_equal_to
    operator = result.get('rule_operator', '').lower()
    valid_operators = ['less_than', 'less_than_or_equal_to', '<', '<=']
    
    # Sometimes DB returns symbol, sometimes text. Handle broadly.
    logic_correct = any(op in operator for op in valid_operators)
    
    if rule_exists and logic_correct:
        score += 20
        feedback_parts.append("Rule logic correct (Positive <= Tested) (+20)")
    elif rule_exists:
        feedback_parts.append(f"Rule logic incorrect (operator: {operator})")

    # 4. Data Corrected (Logic) (20 pts)
    try:
        val_tested = float(result.get('value_tested', 0))
        val_positive = float(result.get('value_positive', 0))
        
        # Logic: Positive must be <= Tested
        if val_positive <= val_tested and val_positive > 0:
            score += 20
            feedback_parts.append(f"Data corrected: Positive({int(val_positive)}) <= Tested({int(val_tested)}) (+20)")
        else:
            feedback_parts.append(f"Data logic error: Positive({int(val_positive)}) > Tested({int(val_tested)})")
    except ValueError:
        feedback_parts.append("Could not parse data values")

    # 5. Data Updated Recently (20 pts)
    if result.get('positive_updated_recently', False):
        score += 20
        feedback_parts.append("Data value updated during task (+20)")
    else:
        feedback_parts.append("Data value not updated")

    # Pass check
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }