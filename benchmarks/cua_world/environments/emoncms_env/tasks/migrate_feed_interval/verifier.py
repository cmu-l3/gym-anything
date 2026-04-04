#!/usr/bin/env python3
import json
import os
import sys

def verify_migrate_feed_interval(traj, env_info, task_info):
    """
    Verifies that:
    1. A backup CSV file was created after task start.
    2. The old feed (10s) was removed (ID changed).
    3. A new feed 'attic_temp' exists with 600s interval.
    4. The input 'attic:temp' logs to this new feed.
    """
    # 1. Load Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    import tempfile
    temp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    # 2. Extract Data
    score = 0
    feedback = []
    
    task_start = result.get('task_start_time', 0)
    backup = result.get('backup', {})
    initial_feed_id = result.get('initial_feed_id')
    current_feed = result.get('current_feed', {})
    input_proc = result.get('input', {}).get('process_list', "")

    # Criterion 1: Backup File (35 pts)
    # Must exist, be created after task start, and have content
    if backup.get('exists'):
        if backup.get('mod_time', 0) > task_start:
            if backup.get('size_bytes', 0) > 100: # Arbitrary small threshold for non-empty CSV
                score += 35
                feedback.append("Backup CSV created successfully.")
            else:
                score += 10
                feedback.append("Backup file exists but is empty/too small.")
        else:
            feedback.append("Backup file exists but matches old timestamp (pre-task?).")
    else:
        feedback.append("Backup CSV file not found.")

    # Criterion 2: Feed Interval (30 pts)
    # Feed must exist and have interval 600
    feed_id = current_feed.get('id')
    interval = current_feed.get('interval')
    
    if feed_id and feed_id != "null":
        if interval == 600:
            score += 30
            feedback.append("New feed has correct 600s interval.")
        else:
            feedback.append(f"Feed exists but interval is {interval}s (expected 600s).")
    else:
        feedback.append("Feed 'attic_temp' not found.")

    # Criterion 3: Feed Replaced (15 pts)
    # Current ID != Initial ID implies deletion and recreation
    if feed_id and initial_feed_id:
        if feed_id != initial_feed_id:
            score += 15
            feedback.append("Old feed was replaced (ID changed).")
        else:
            feedback.append("Feed ID unchanged (did you delete the old one?).")
    
    # Criterion 4: Input Process Updated (20 pts)
    # Process list should contain "1:<feed_id>"
    # "1" is the process ID for "Log to feed" in Emoncms
    expected_process = f"1:{feed_id}"
    if input_proc and expected_process in input_proc:
        score += 20
        feedback.append("Input logging correctly configured.")
    else:
        feedback.append(f"Input process list incorrect. Expected to find '{expected_process}' in '{input_proc}'.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }