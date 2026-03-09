#!/usr/bin/env python3
"""
Verifier for retire_location@1.
Verifies that the specified location was retired with the correct reason.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retire_location(traj, env_info, task_info):
    """
    Verify the agent retired 'Satellite Clinic East' with the correct reason.
    
    Scoring Breakdown (100 pts total):
    - Location is retired (API check): 35 pts
    - Location is retired (DB check): 10 pts
    - Retire reason matches expected text (API+DB): 30 pts
    - Location still exists (not purged): 15 pts
    - Retirement happened AFTER task start: 10 pts
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_reason_fragment = "community health drive"
    
    # 2. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Data
    api_data = result.get('api_verification', {})
    db_data = result.get('db_verification', {})
    task_start = result.get('task_start_ts', 0)
    initial_retired = result.get('initial_retired_state', 'false').lower() == 'true'

    score = 0
    feedback = []
    
    # Check 0: Anti-Gaming - Was it already retired?
    if initial_retired:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Setup Error: Location was already retired when task started. Zero score assigned."
        }

    # Criterion 1: Location Exists (Not Purged) (15 pts)
    # If the agent deleted the location instead of retiring it, this fails.
    if api_data.get('exists') and db_data.get('exists'):
        score += 15
        feedback.append("Location preserved (not purged).")
    else:
        feedback.append("FAIL: Location was deleted/purged from the system.")
        # If deleted, we can't verify other criteria effectively
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion 2: Retired Status - API (35 pts)
    if api_data.get('retired'):
        score += 35
        feedback.append("API confirms location is retired.")
    else:
        feedback.append("FAIL: API shows location is NOT retired.")

    # Criterion 3: Retired Status - DB (10 pts)
    if db_data.get('retired'):
        score += 10
        feedback.append("DB confirms location is retired.")
    else:
        feedback.append("FAIL: DB shows location is NOT retired.")

    # Criterion 4: Retire Reason (30 pts)
    # Check both API and DB for robustness
    api_reason = api_data.get('reason', '').lower()
    db_reason = db_data.get('reason', '').lower()
    
    reason_match = False
    if expected_reason_fragment in api_reason:
        reason_match = True
    # DB reason sometimes has different whitespace, check loosely
    elif expected_reason_fragment in db_reason:
        reason_match = True
        
    if reason_match:
        score += 30
        feedback.append("Retire reason matches requirements.")
    else:
        feedback.append(f"FAIL: Retire reason incorrect. Expected '{expected_reason_fragment}' in reason.")
        feedback.append(f"Got: '{api_reason}'")

    # Criterion 5: Timestamp Validity (10 pts)
    # Ensure the database modification happened during the task
    db_ts = db_data.get('retire_timestamp', 0)
    if db_ts > task_start:
        score += 10
        feedback.append("Action verified by timestamp.")
    else:
        feedback.append("FAIL: Retirement timestamp predates task start or is missing.")

    # Final Evaluation
    passed = score >= 45 and api_data.get('retired')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }