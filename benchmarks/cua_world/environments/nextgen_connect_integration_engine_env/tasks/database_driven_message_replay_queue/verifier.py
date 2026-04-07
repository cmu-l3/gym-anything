#!/usr/bin/env python3
"""
Verifier for Database Driven Message Replay Queue task.

Verification Logic:
1. Database State (40 pts):
   - All initially PENDING rows (ids 1, 2, 4) must now be PROCESSED.
   - Updates must have happened during the task (timestamp check).
2. File Output (30 pts):
   - Exactly 3 output files should exist.
   - Files should contain HL7 data.
3. Channel Configuration (30 pts):
   - Channel should exist and be in STARTED/deployed state.
   - Implicitly verified by the DB updates and file creation (functional verification).
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_database_replay(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    task_start = result.get('task_start', 0)
    db_state = result.get('db_state', {})
    file_output = result.get('file_output', {})
    channel_info = result.get('channel_info', {})

    score = 0
    feedback = []

    # 1. Database Verification
    target_rows = db_state.get('target_rows', [])
    processed_count = db_state.get('processed_count', 0)
    pending_count = db_state.get('pending_count', 0)

    # Check if target rows are processed
    target_success = True
    timestamps_valid = True
    
    if not target_rows:
        target_success = False
        feedback.append("No target rows found in database report.")
    else:
        for row in target_rows:
            rid = row.get('id')
            status = row.get('status')
            ts = row.get('processed_ts')
            
            if status != 'PROCESSED':
                target_success = False
                feedback.append(f"Row {rid} status is {status} (expected PROCESSED).")
            
            # Anti-gaming: Check timestamp
            if ts is None or ts < task_start:
                timestamps_valid = False
                feedback.append(f"Row {rid} has invalid timestamp (pre-dated or null).")

    if target_success and len(target_rows) == 3:
        score += 20
        feedback.append("All target database rows updated to PROCESSED.")
    
    if timestamps_valid and target_success:
        score += 20
        feedback.append("Database update timestamps are valid (occurred during task).")
    
    if pending_count == 0:
        feedback.append("No PENDING rows remain.")
    else:
        feedback.append(f"Warning: {pending_count} rows are still PENDING.")

    # 2. File Output Verification
    file_count = file_output.get('count', 0)
    valid_content = file_output.get('valid_content', False)

    if file_count == 3:
        score += 20
        feedback.append("Correct number of output files created (3).")
    elif file_count > 0:
        score += 10
        feedback.append(f"Output files created, but count mismatch (Found {file_count}, expected 3).")
    else:
        feedback.append("No output files found.")

    if valid_content:
        score += 10
        feedback.append("Output files contain valid HL7 content.")

    # 3. Channel Status
    status = channel_info.get('status', 'UNKNOWN')
    if status in ['STARTED', 'DEPLOYED', 'Running']: # NextGen API returns various states depending on version
        score += 30
        feedback.append(f"Channel is deployed and running ({status}).")
    elif status != 'UNKNOWN' and status != '':
        score += 10 # Partial credit for creating but maybe not starting
        feedback.append(f"Channel exists but status is {status}.")
    else:
        # If DB was updated and files created, the channel MUST have been running at some point
        if target_success and file_count > 0:
            score += 30
            feedback.append("Channel verified functional via data processing evidence.")
        else:
            feedback.append("Channel status could not be verified.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }