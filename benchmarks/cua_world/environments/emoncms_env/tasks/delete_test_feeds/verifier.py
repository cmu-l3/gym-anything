#!/usr/bin/env python3
"""
Verifier for delete_test_feeds task.

Scoring Logic:
- 15 points per correct test feed deleted (4 feeds = 60 points)
- 25 points if ALL production feeds are intact
- 15 points if the total count difference is exactly 4
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_test_feeds(traj, env_info, task_info):
    """
    Verify that the 4 test feeds were deleted and production feeds remain.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Test Feeds (15 pts each)
    test_feeds_status = result.get("test_feeds_status", {})
    deleted_count = 0
    
    expected_feeds = [
        "test_voltage_check",
        "test_ct_sensor_1",
        "test_calibration_run",
        "test_mqtt_connection"
    ]
    
    for feed in expected_feeds:
        is_deleted = test_feeds_status.get(feed, False)
        if is_deleted:
            score += 15
            deleted_count += 1
            feedback_parts.append(f"[PASS] {feed} deleted")
        else:
            feedback_parts.append(f"[FAIL] {feed} NOT deleted")

    # 2. Check Production Feeds (25 pts)
    prod_intact = result.get("production_feeds_intact", False)
    if prod_intact:
        score += 25
        feedback_parts.append("[PASS] Production feeds intact")
    else:
        missing = result.get("missing_production_ids", "")
        feedback_parts.append(f"[FAIL] Production feeds missing (IDs: {missing})")

    # 3. Check Total Count Logic (15 pts)
    initial_count = int(result.get("initial_count", 0))
    final_count = int(result.get("final_count", 0))
    diff = initial_count - final_count
    
    if diff == 4:
        score += 15
        feedback_parts.append("[PASS] Total feed count decreased by exactly 4")
    else:
        feedback_parts.append(f"[FAIL] Count delta incorrect (Initial: {initial_count}, Final: {final_count}, Diff: {diff})")

    # Final Result
    passed = (score >= 60) and prod_intact and (deleted_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }