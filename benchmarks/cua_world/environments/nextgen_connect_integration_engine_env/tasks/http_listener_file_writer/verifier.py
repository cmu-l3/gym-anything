#!/usr/bin/env python3
"""
Verifier for http_listener_file_writer task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_http_listener_file_writer(traj, env_info, task_info):
    """
    Verify that the ADT Audit HTTP channel was created and works correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    # Extract metrics
    channel_found = result.get('channel_found', False)
    db_confirmed = result.get('db_confirmed', False)
    http_listener = result.get('http_listener', False)
    port_correct = result.get('port_correct', False)
    file_writer = result.get('file_writer', False)
    path_correct = result.get('path_correct', False)
    status = result.get('status', 'UNKNOWN')
    stats_received = result.get('stats_received', 0)
    file_created = result.get('file_created', False)
    hl7_content = result.get('hl7_content', False)
    test_message_processed = result.get('test_message_processed', False)
    test_file_written = result.get('test_file_written', False)

    score = 0
    feedback_parts = []

    # 1. Channel Creation (30 pts)
    if channel_found or db_confirmed:
        score += 15
        feedback_parts.append("Channel 'ADT_Audit_HTTP' created.")
        
        if http_listener and port_correct:
            score += 10
            feedback_parts.append("HTTP Listener on port 6661 configured.")
        elif http_listener:
            score += 5
            feedback_parts.append("HTTP Listener configured (wrong port).")
        else:
            feedback_parts.append("HTTP Listener NOT configured correctly.")
            
        if file_writer and path_correct:
            score += 5  # Small points for config, bigger points for actual file output
            feedback_parts.append("File Writer destination configured.")
        elif file_writer:
            feedback_parts.append("File Writer configured (wrong path).")
    else:
        feedback_parts.append("Channel 'ADT_Audit_HTTP' NOT found.")

    # 2. Deployment Status (15 pts)
    if status == 'STARTED':
        score += 15
        feedback_parts.append("Channel is STARTED.")
    elif status != 'UNKNOWN':
        score += 5
        feedback_parts.append(f"Channel status is {status} (expected STARTED).")
    else:
        feedback_parts.append("Channel is NOT deployed/started.")

    # 3. Message Processing (25 pts)
    # Check if stats show received messages OR if our test message worked
    if stats_received > 0 or test_message_processed:
        score += 25
        feedback_parts.append(f"Messages processed (Stats: {stats_received}).")
    else:
        feedback_parts.append("No messages processed.")

    # 4. File Output Verification (30 pts)
    if file_created and hl7_content:
        score += 30
        feedback_parts.append("Output file created with valid HL7 content.")
    elif file_created:
        score += 15
        feedback_parts.append("Output file created but HL7 content verification failed.")
    elif test_file_written:
        # Fallback if agent's file was deleted but our test file worked
        score += 30
        feedback_parts.append("Active test confirmed file writing works.")
    else:
        feedback_parts.append("No output files found in /home/ga/output/.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }