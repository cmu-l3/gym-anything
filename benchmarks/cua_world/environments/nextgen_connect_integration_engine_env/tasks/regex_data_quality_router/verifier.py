#!/usr/bin/env python3
import json
import os
import tempfile

def verify_regex_router(traj, env_info, task_info):
    """
    Verifies the Regex Data Quality Router task.
    Scoring based on functional black-box testing performed in export_result.sh.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    passed = False

    # 1. Channel Existence & Status (10 pts)
    if result.get("channel_found", False):
        if result.get("channel_status") == "STARTED":
            score += 10
            feedback.append("Channel 'MRN_Quality_Firewall' is deployed and STARTED.")
        else:
            score += 5
            feedback.append(f"Channel found but status is {result.get('channel_status')} (expected STARTED).")
    else:
        feedback.append("Channel 'MRN_Quality_Firewall' not found.")
        return {"passed": False, "score": 0, "feedback": "Channel not found."}

    # 2. Valid Message Processing (45 pts total)
    # 2a. File Creation (20 pts)
    valid_content = result.get("test_a_content_sample", "")
    if result.get("test_a_valid_file_exists", False):
        score += 20
        feedback.append("Valid message routed to /home/ga/valid.")
        
        # 2b. Transformation Check (25 pts)
        # We sent ID '999999', expect 'MRN-999999'
        if "MRN-999999" in valid_content:
            score += 25
            feedback.append("Valid message transformation (MRN- prefix) correct.")
        elif "999999" in valid_content:
            feedback.append("Valid message found, but 'MRN-' prefix missing.")
            score += 5
        else:
            feedback.append("Valid output file content unexpected.")
    else:
        feedback.append("No output file found in /home/ga/valid for valid message.")

    # 3. Invalid Message Processing (45 pts total)
    # 3a. File Creation (20 pts)
    quarantine_content = result.get("test_b_content_sample", "")
    if result.get("test_b_quarantine_file_exists", False):
        score += 20
        feedback.append("Invalid message routed to /home/ga/quarantine.")
        
        # 3b. Content Check (25 pts)
        # We sent ID 'BAD123', expect 'Invalid MRN detected: BAD123'
        if "Invalid MRN detected" in quarantine_content and "BAD123" in quarantine_content:
            score += 25
            feedback.append("Quarantine error message format correct.")
        elif "BAD123" in quarantine_content:
            score += 10
            feedback.append("Quarantine file contains ID but wrong format.")
        else:
            feedback.append("Quarantine file content incorrect.")
    else:
        feedback.append("No output file found in /home/ga/quarantine for invalid message.")

    if score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }