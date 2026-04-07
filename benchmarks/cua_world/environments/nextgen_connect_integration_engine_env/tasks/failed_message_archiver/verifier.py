#!/usr/bin/env python3
"""
Verifier for Failed Message Archiver Task
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_failed_message_archiver(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created the correct channel
    2. Configured it to Fail Fast (No Queue, No Retry)
    3. Implemented an archival script
    4. Successfully archived a failed message
    """
    
    # 1. Setup Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve Result JSON
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

    # 3. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: Channel Creation (10 pts)
    if result.get("channel_exists", False):
        score += 10
        feedback.append("Channel 'Fail_Safe_Archiver' created.")
    else:
        feedback.append("Channel 'Fail_Safe_Archiver' NOT found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 2: Fail Fast Configuration (20 pts)
    # Queue disabled (10) + Retry zero (10)
    if result.get("queue_disabled", False):
        score += 10
        feedback.append("Queueing correctly disabled.")
    else:
        feedback.append("Queueing was NOT disabled (critical for Fail Fast).")
        
    if result.get("retry_zero", False):
        score += 10
        feedback.append("Retry count set to 0.")
    else:
        feedback.append("Retry count was not 0.")

    # Criterion 3: Script Detection (10 pts)
    if result.get("script_detected", False):
        score += 10
        feedback.append("Archival script logic detected.")
    else:
        feedback.append("No file write logic detected in channel script.")

    # Criterion 4: Execution Verification (60 pts)
    # Error Stat Incremented (15) + File Created (25) + Content Match (20)
    if result.get("error_stat_incremented", False):
        score += 15
        feedback.append("Channel correctly reported an ERROR.")
    else:
        feedback.append("Channel did not report any errors (did you send the message?).")
        
    if result.get("file_archived", False):
        score += 25
        feedback.append("Archived file found in /tmp/failed_messages/.")
        
        if result.get("archived_file_match", False):
            score += 20
            feedback.append("Archived file content matches original message.")
        else:
            feedback.append("Archived file content did NOT match original message.")
    else:
        feedback.append("No archived file found in /tmp/failed_messages/.")

    # 4. Final Assessment
    # Pass threshold: 75 (Must have channel + config + file created)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }