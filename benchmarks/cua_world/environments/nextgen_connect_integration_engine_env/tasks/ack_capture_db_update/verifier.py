#!/usr/bin/env python3
"""Verifier for ack_capture_db_update task."""

import json
import tempfile
import os

def verify_ack_capture_db_update(traj, env_info, task_info):
    """
    Verify that the channel correctly processes orders, gets ACKs, and updates the DB.
    
    Verification Logic:
    1. Static Check: Did the sample order (ORD-001) get updated in the DB?
    2. Dynamic Check: Verification script sent a new random Order ID. Did it get updated?
       (This proves the agent didn't just manually update the sample row via SQL)
    3. Infrastructure Check: Is the channel listening on the correct port?
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
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

    # Extract Metrics
    sample_updated = result.get("sample_updated", False)
    dynamic_success = result.get("dynamic_test_success", False)
    channel_port_open = result.get("channel_port_open", False)
    dynamic_value = result.get("dynamic_value_found", "")
    expected_value = result.get("expected_dynamic_value", "")
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Channel Listening (20 pts)
    if channel_port_open:
        score += 20
        feedback_parts.append("Channel is listening on port 6661.")
    else:
        feedback_parts.append("Channel is NOT listening on port 6661.")

    # Criterion 2: Sample Data Processed (30 pts)
    if sample_updated:
        score += 30
        feedback_parts.append("Sample order ORD-001 was correctly updated in the database.")
    else:
        feedback_parts.append("Sample order ORD-001 was NOT updated in the database.")

    # Criterion 3: Dynamic Verification (50 pts) - CRITICAL
    # This ensures the logic works for ANY message, not just the one the agent sees.
    if dynamic_success:
        score += 50
        feedback_parts.append(f"Dynamic test passed: {dynamic_value} matched expected.")
    else:
        feedback_parts.append(f"Dynamic test failed. Expected '{expected_value}' in DB, found '{dynamic_value}'.")
        if not channel_port_open:
            feedback_parts.append("(Dynamic test likely failed because channel is not running)")

    # Pass Threshold
    # Must pass dynamic test to prove the logic is implemented generally
    passed = dynamic_success and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }