#!/usr/bin/env python3
"""
Verifier for outbound_nack_handling task.
Verifies that the agent correctly handled a negative acknowledgment (NACK)
by overriding the message status to ERROR and logging the specific error message.
"""

import json
import tempfile
import os

def verify_outbound_nack_handling(traj, env_info, task_info):
    """
    Verify the Outbound NACK Handling task.
    
    Criteria:
    1. Channel exists (20 pts)
    2. Connection made to simulator (20 pts)
    3. Message status is ERROR (30 pts) - This proves response transformer logic
    4. Log file contains error text (30 pts) - This proves error extraction
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Extract data
    channel_found = result.get('channel_found', False)
    message_status = result.get('message_status', 'UNKNOWN')
    log_exists = result.get('log_exists', False)
    log_content_match = result.get('log_content_match', False)
    dest_connected = result.get('destination_connected', False)
    
    score = 0
    feedback = []
    
    # Check 1: Channel Exists
    if channel_found:
        score += 20
        feedback.append("Channel 'Lab_Order_Sender' found.")
    else:
        feedback.append("Channel 'Lab_Order_Sender' NOT found.")
        
    # Check 2: Connectivity
    if dest_connected:
        score += 20
        feedback.append("Successfully connected to the simulated LIS.")
    else:
        feedback.append("No connection detected to the simulated LIS (port 6699).")
        
    # Check 3: Message Status (The Core Technical Requirement)
    # Default behavior for NACK is often SENT (green) unless overridden.
    if message_status == "ERROR":
        score += 30
        feedback.append("Message status correctly set to ERROR in dashboard.")
    elif message_status == "SENT":
        feedback.append("Message status is SENT. Failed to override status to ERROR based on NACK.")
    else:
        feedback.append(f"Message status is {message_status} (Expected: ERROR).")
        
    # Check 4: Log File Extraction
    if log_content_match:
        score += 30
        feedback.append("Error log file created with correct error text.")
    elif log_exists:
        score += 15
        feedback.append("Log file exists, but text does not match expected 'Simulated Patient ID Error'.")
    else:
        feedback.append("Log file '/home/ga/lab_rejections.log' was not created.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }