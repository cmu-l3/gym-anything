#!/usr/bin/env python3
"""
Verifier for auth_data_model task.

VERIFICATION METRICS:
1. Data Model exists and is newly created during task session.
2. Root object constraint correctly references the "security_logs" index.
3. Model is hierarchical (contains >= 2 child objects filtering data).
4. Model defines field constraints (contains >= 3 field extractions).
5. Model acceleration is successfully toggled on.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_auth_data_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract dynamic metadata thresholds
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('model_name', 'Authentication_Events')
    required_index = metadata.get('required_index', 'security_logs')
    min_children = metadata.get('min_child_objects', 2)
    min_fields = metadata.get('min_fields', 3)

    # Read the extracted result file from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/auth_data_model_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Anti-gaming check: Make sure model was created *during* the task
    if not result.get('is_newly_created', True):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"FAIL: Data model '{expected_name}' existed before the task started. Must create a new one."
        }
    
    # Criterion 1: Model exists (20 pts)
    model_found = result.get('model_found', False)
    actual_name = result.get('model_name_actual', '')
    if model_found:
        if actual_name == expected_name:
            score += 20
            feedback_parts.append(f"Data model '{expected_name}' found")
        else:
            score += 15
            feedback_parts.append(f"Data model found with incorrect casing ('{actual_name}')")
    else:
        feedback_parts.append(f"FAIL: Data model '{expected_name}' NOT found in Splunk")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check for REST parsing errors (meaning Splunk couldn't validate the object schema)
    if result.get('parse_error'):
        feedback_parts.append(f"FAIL: Could not parse model schema ({result['parse_error']})")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Base search references security_logs (20 pts)
    root_search = result.get('root_search', '').lower()
    if required_index in root_search:
        score += 20
        feedback_parts.append(f"Root dataset correctly references '{required_index}'")
    else:
        feedback_parts.append(f"FAIL: Root dataset constraints do not reference '{required_index}' (found: '{root_search}')")

    # Criterion 3: >= 2 child objects (20 pts)
    child_objects = result.get('child_objects_count', 0)
    if child_objects >= min_children:
        score += 20
        feedback_parts.append(f"Has {child_objects} child datasets (>= {min_children})")
    elif child_objects > 0:
        score += 10
        feedback_parts.append(f"Has only {child_objects} child dataset(s), expected >= {min_children}")
    else:
        feedback_parts.append("FAIL: No child datasets defined")

    # Criterion 4: >= 3 field definitions (20 pts)
    fields_count = result.get('fields_count', 0)
    if fields_count >= min_fields:
        score += 20
        feedback_parts.append(f"Has {fields_count} field definitions (>= {min_fields})")
    elif fields_count > 0:
        score += 10
        feedback_parts.append(f"Has only {fields_count} field definition(s), expected >= {min_fields}")
    else:
        feedback_parts.append("FAIL: No fields defined in the schema")

    # Criterion 5: Acceleration enabled (20 pts)
    if result.get('acceleration_enabled', False):
        score += 20
        feedback_parts.append("Acceleration is enabled")
    else:
        feedback_parts.append("FAIL: Acceleration is NOT enabled")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }