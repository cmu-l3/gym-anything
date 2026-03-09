#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tune_campaign_dialing(traj, env_info, task_info):
    """
    Verify the Vicidial campaign tuning task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_statuses = set(metadata.get('expected_statuses', ["NEW", "BUSY", "N"]))
    expected_sql = metadata.get('expected_sql', "called_count < 5").replace(" ", "").lower()
    expected_timeout = int(metadata.get('expected_timeout', 45))
    expected_drop = int(metadata.get('expected_drop_percent', 2))
    filter_id = metadata.get('filter_id', 'MAX_5_TRIES')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get('campaign_exists'):
        return {"passed": False, "score": 0, "feedback": "Campaign NURTURE not found in database."}

    score = 0
    feedback = []

    # 1. Verify Dial Statuses (25 pts)
    # DB stores as space padded string: " NEW BUSY N "
    actual_statuses_str = result.get('dial_statuses', '')
    actual_statuses = set(actual_statuses_str.strip().split())
    
    # Check if all expected statuses are present
    missing_statuses = expected_statuses - actual_statuses
    if not missing_statuses:
        score += 25
        feedback.append("Dial Statuses correct.")
    else:
        feedback.append(f"Missing dial statuses: {missing_statuses}.")

    # 2. Verify Filter Creation & SQL (25 pts)
    actual_sql = result.get('filter_sql_content', '').replace(" ", "").lower()
    
    # Check if SQL matches logically (ignoring whitespace/case)
    if actual_sql == expected_sql:
        score += 25
        feedback.append("Filter SQL correct.")
    elif actual_sql:
        # Partial credit if filter exists but SQL is wrong
        score += 5
        feedback.append(f"Filter created but SQL incorrect. Got: '{result.get('filter_sql_content')}'")
    else:
        feedback.append("Filter MAX_5_TRIES not found.")

    # 3. Verify Filter Assignment (15 pts)
    actual_filter_id = result.get('lead_filter_id', '')
    if actual_filter_id == filter_id:
        score += 15
        feedback.append("Filter assigned to campaign.")
    else:
        feedback.append(f"Wrong filter assigned. Expected {filter_id}, got {actual_filter_id}.")

    # 4. Verify Timeout (20 pts)
    try:
        actual_timeout = int(result.get('dial_timeout', 0))
        if actual_timeout == expected_timeout:
            score += 20
            feedback.append("Dial Timeout correct.")
        else:
            feedback.append(f"Timeout incorrect: {actual_timeout}.")
    except:
        feedback.append("Invalid timeout value.")

    # 5. Verify Drop Percentage (15 pts)
    try:
        actual_drop = int(float(result.get('adaptive_dropped_percentage', 0))) # Handle 2.0 vs 2
        if actual_drop == expected_drop:
            score += 15
            feedback.append("Drop Percentage correct.")
        else:
            feedback.append(f"Drop Percentage incorrect: {actual_drop}.")
    except:
        feedback.append("Invalid drop percentage value.")

    # Pass logic: Must have statuses and filter assigned correctly as a baseline (40 pts minimum implied, but threshold set higher)
    # Threshold 65 means they need most things correct.
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }