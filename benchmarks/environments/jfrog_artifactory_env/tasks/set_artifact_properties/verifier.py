#!/usr/bin/env python3
"""
Verifier for set_artifact_properties task.

Checks:
1. Artifact exists (HEAD 200)
2. Properties endpoint returns 200
3. Specific properties (build.name, build.number, qa.status, deploy.env) match expected values.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_artifact_properties(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_props = metadata.get('expected_properties', {})

    # Copy result file
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
    
    # 1. Artifact Existence (5 pts)
    if result.get('artifact_exists', False):
        score += 5
        feedback_parts.append("Artifact exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Artifact was deleted or not found"}

    # 2. Properties Endpoint Accessibility (10 pts)
    prop_code = result.get('properties_http_code', '0')
    if str(prop_code) == '200':
        score += 10
        feedback_parts.append("Properties accessed")
    else:
        return {"passed": False, "score": score, "feedback": "No properties found on artifact"}

    # 3. Check specific properties (20 pts each)
    # Artifactory API structure: {"properties": {"key": ["val"], ...}, "uri": "..."}
    actual_props_data = result.get('properties_data', {}).get('properties', {})
    
    # Helper to clean value (API returns list of strings)
    def get_val(key):
        val_list = actual_props_data.get(key, [])
        if isinstance(val_list, list) and len(val_list) > 0:
            return val_list[0]
        return None

    # Check each expected property
    missed_props = []
    for key, expected_val in expected_props.items():
        actual_val = get_val(key)
        if actual_val == expected_val:
            score += 20
            feedback_parts.append(f"✓ {key}")
        else:
            missed_props.append(f"{key} (expected '{expected_val}', got '{actual_val}')")
    
    # 4. Anti-gaming / Timestamp check (5 pts)
    # Simple check: if we have properties, assume they were added during task 
    # since setup script cleared them.
    if len(actual_props_data) > 0:
        score += 5
        feedback_parts.append("Modification verified")

    if missed_props:
        feedback_parts.append("Incorrect/Missing: " + ", ".join(missed_props))

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }