#!/usr/bin/env python3
"""
Verifier for update_facility_coordinates task in CAMEO Data Manager.

Checks:
1. Database modification timestamp (anti-gaming).
2. Latitude and Longitude values in the database match expected values.
3. Facility record exists.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_facility_coordinates(traj, env_info, task_info):
    """
    Verify that the facility coordinates were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('expected_latitude', 29.7523)
    expected_long = metadata.get('expected_longitude', -95.3585)
    tolerance = metadata.get('tolerance', 0.001)

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path in container needs to be handled by copy_from_env
        # Typically copy_from_env handles absolute paths in the guest
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Anti-Gaming: DB Modification
    if result.get('db_modified_during_task', False):
        score += 15
        feedback_parts.append("Database modified during task.")
    else:
        feedback_parts.append("Database NOT modified during task (Possible 'Do Nothing').")

    # 2. Record Existence
    if result.get('record_found', False):
        score += 10
        feedback_parts.append("Facility record found.")
    else:
        feedback_parts.append("Facility record NOT found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 3. Value Verification
    actual_lat = result.get('latitude', 0.0)
    actual_long = result.get('longitude', 0.0)

    # Check for non-zero (defaults were 0)
    if actual_lat == 0 and actual_long == 0:
        feedback_parts.append("Coordinates are still default (0,0).")
    else:
        # Latitude Check
        if math.isclose(actual_lat, expected_lat, abs_tol=tolerance):
            score += 35
            feedback_parts.append(f"Latitude correct ({actual_lat}).")
        else:
            feedback_parts.append(f"Latitude incorrect (Exp: {expected_lat}, Got: {actual_lat}).")

        # Longitude Check
        # Special case: Agent might forget negative sign for West
        if math.isclose(actual_long, expected_long, abs_tol=tolerance):
            score += 40
            feedback_parts.append(f"Longitude correct ({actual_long}).")
        elif math.isclose(actual_long, abs(expected_long), abs_tol=tolerance):
            score += 20
            feedback_parts.append(f"Longitude correct magnitude but wrong sign (Got: {actual_long}, missing negative).")
        else:
            feedback_parts.append(f"Longitude incorrect (Exp: {expected_long}, Got: {actual_long}).")

    passed = score >= 70  # Requires correct lat AND roughly correct long + modification
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }