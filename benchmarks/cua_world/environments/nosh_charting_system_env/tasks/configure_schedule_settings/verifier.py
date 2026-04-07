#!/usr/bin/env python3
"""
Verifier for configure_schedule_settings task in NOSH ChartingSystem.

Verifies that the agent logged in as the provider and changed the 
schedule increment (slot duration) from 20 to 15 minutes.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_schedule_settings(traj, env_info, task_info):
    """
    Verify the schedule increment configuration.
    
    Criteria:
    1. Database value for 'schedule_increment' must be '15' (Primary).
    2. Value must have changed from the initial '20' (Anti-gaming).
    3. Application must be running at the end.
    """
    
    # 1. Setup: Retrieve result file from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    final_val = result.get("final_schedule_increment", "unknown")
    app_running = result.get("app_was_running", False)
    
    # Metadata
    metadata = task_info.get("metadata", {})
    expected_val = str(metadata.get("expected_value", "15"))
    initial_val = str(metadata.get("initial_value", "20"))

    score = 0
    feedback_parts = []
    passed = False

    # 3. Scoring Logic
    
    # Criterion 1: Check if the value matches expectation (15) - 80 points
    if str(final_val) == expected_val:
        score += 80
        feedback_parts.append(f"✅ Schedule increment successfully set to {expected_val} minutes.")
    elif str(final_val) == initial_val:
        feedback_parts.append(f"❌ Schedule increment unchanged (still {initial_val} minutes).")
    else:
        feedback_parts.append(f"❌ Schedule increment set to incorrect value: {final_val} (expected {expected_val}).")

    # Criterion 2: Check if value actually changed (Anti-gaming) - 10 points
    # (Implicitly covered by checking == expected, but explicit check handles edge cases)
    if str(final_val) != initial_val:
        score += 10
        feedback_parts.append("✅ Configuration was modified.")
    else:
        feedback_parts.append("⚠️ No changes detected in database.")

    # Criterion 3: App running - 10 points
    if app_running:
        score += 10
        feedback_parts.append("✅ Application healthy.")
    else:
        feedback_parts.append("❌ Application was not running at verification time.")

    # 4. Final Determination
    if score == 100:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": {
            "final_value": final_val,
            "expected_value": expected_val,
            "initial_value": initial_val
        }
    }