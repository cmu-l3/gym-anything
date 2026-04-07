#!/usr/bin/env python3
"""
Verifier for build_custom_module task.

Verification Strategy:
1. File System Check: Did the agent create the package and click 'Deploy'?
2. Database Schema Verification: Did the deploy actually create the custom tables?
3. Column Checks: Did the agent correctly specify the custom fields and their types before deploying?
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_custom_module(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/build_custom_module_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Directory Checks (Filesystem)
    if result.get('package_dir_exists'):
        score += 10
        feedback.append("Package directory created")
    else:
        feedback.append("Package directory missing")

    if result.get('module_dir_exists'):
        score += 10
        feedback.append("Deployed module directory exists")
    else:
        feedback.append("Deployed module directory missing")

    # 2. Database Table Presence
    table_exists = result.get('table_exists', False)
    if table_exists:
        score += 30
        feedback.append("Database tables generated (Deploy successful)")
    else:
        feedback.append("Database tables missing (Module was not Deployed)")

    # 3. Custom Fields (Schema columns)
    cols = result.get('columns', {})
    
    if 'vin_number' in cols:
        score += 15
        feedback.append("Field 'vin_number' successfully configured")
    else:
        feedback.append("Field 'vin_number' missing from database")

    if 'license_plate' in cols:
        score += 15
        feedback.append("Field 'license_plate' successfully configured")
    else:
        feedback.append("Field 'license_plate' missing from database")

    if 'payload_capacity' in cols:
        dtype = cols['payload_capacity']
        # Depending on MariaDB version and SuiteCRM int map, could be int or tinyint or bigint
        if 'int' in dtype:
            score += 20
            feedback.append("Field 'payload_capacity' configured with correct type (Integer)")
        else:
            score += 10
            feedback.append(f"Field 'payload_capacity' exists but has incorrect type: {dtype}")
    else:
        feedback.append("Field 'payload_capacity' missing from database")

    # Pass logic: Must have clicked deploy successfully and configured at least some fields correctly.
    key_criteria_met = table_exists and (score >= 70)

    return {
        "passed": key_criteria_met,
        "score": score,
        "feedback": " | ".join(feedback)
    }