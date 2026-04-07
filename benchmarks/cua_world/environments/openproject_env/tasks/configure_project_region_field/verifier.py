#!/usr/bin/env python3
"""
Verifier for configure_project_region_field task.
Checks if the custom field was created correctly and applied to the project.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_project_region_field(traj, env_info, task_info):
    """
    Verify the OpenProject custom field configuration.
    
    Criteria:
    1. Custom Field "Owning Region" exists (20 pts)
    2. Format is "list" (15 pts)
    3. Options match exactly ["North America", "EMEA", "APAC"] (25 pts)
    4. "Mobile Banking App" has a value set (20 pts)
    5. The set value is "EMEA" (20 pts)
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

    metadata = task_info.get('metadata', {})
    expected_options = set(metadata.get('expected_options', ["North America", "EMEA", "APAC"]))
    expected_value = metadata.get('expected_value', "EMEA")

    score = 0
    feedback = []

    # 1. Check Field Existence
    if result.get('field_exists'):
        score += 20
        feedback.append("Custom field 'Owning Region' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Custom field 'Owning Region' not found."}

    # 2. Check Format
    fmt = result.get('field_format', '').lower()
    if fmt == 'list':
        score += 15
        feedback.append("Field format is correct (List).")
    else:
        feedback.append(f"Field format mismatch: expected 'list', got '{fmt}'.")

    # 3. Check Options
    actual_options = set(result.get('options', []))
    # Check if all expected options are present
    missing = expected_options - actual_options
    extra = actual_options - expected_options
    
    if not missing and not extra:
        score += 25
        feedback.append("Options match exactly.")
    elif not missing:
        # Penalize slightly for extras but give partial credit
        score += 20
        feedback.append(f"Expected options found, but extras present: {extra}")
    else:
        score += 0
        feedback.append(f"Missing required options: {missing}")

    # 4. Check Project Value Assignment
    val_resolved = result.get('project_value_resolved')
    
    if val_resolved is not None:
        score += 20
        feedback.append("Mobile Banking App has a value set.")
        
        # 5. Check Specific Value
        if val_resolved == expected_value:
            score += 20
            feedback.append(f"Correct value assigned: {expected_value}.")
        else:
            feedback.append(f"Wrong value assigned: expected '{expected_value}', got '{val_resolved}'.")
    else:
        feedback.append("Mobile Banking App has no value set for this field.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }