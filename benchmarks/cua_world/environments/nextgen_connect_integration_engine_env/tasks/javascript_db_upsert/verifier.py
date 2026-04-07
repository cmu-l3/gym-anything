#!/usr/bin/env python3
"""Verifier for javascript_db_upsert task."""

import json
import tempfile
import os

def verify_javascript_db_upsert(traj, env_info, task_info):
    """Verify the Javascript DB Upsert task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/javascript_db_upsert_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criteria
    channel_exists = result.get('channel_exists', False)
    connector_correct = result.get('connector_type_correct', False)
    script_valid = result.get('script_content_valid', False)
    insert_passed = result.get('insert_test_passed', False)
    update_passed = result.get('update_test_passed', False)

    score = 0
    feedback_parts = []

    # 1. Channel Creation (10 pts)
    if channel_exists:
        score += 10
        feedback_parts.append("Channel 'Census_Upsert_Processor' created.")
    else:
        feedback_parts.append("Channel 'Census_Upsert_Processor' not found.")

    # 2. Correct Connector (20 pts)
    if connector_correct:
        score += 20
        feedback_parts.append("Destination uses JavaScript Writer.")
    else:
        if channel_exists:
            feedback_parts.append("Destination does NOT use JavaScript Writer (incorrect connector type).")

    # 3. Script Heuristics (10 pts)
    if script_valid:
        score += 10
        feedback_parts.append("Script contains necessary DB keywords.")
    else:
        feedback_parts.append("Script missing DB connection or SQL keywords.")

    # 4. Functional Testing (60 pts total)
    # Insert (30 pts)
    if insert_passed:
        score += 30
        feedback_parts.append("Functional Test: INSERT logic working.")
    else:
        feedback_parts.append("Functional Test: INSERT logic failed.")

    # Update (30 pts)
    if update_passed:
        score += 30
        feedback_parts.append("Functional Test: UPDATE logic working.")
    else:
        feedback_parts.append("Functional Test: UPDATE logic failed (upsert not handling updates correctly).")

    # Pass Threshold: Need functional tests to pass (at least one) and correct setup
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }