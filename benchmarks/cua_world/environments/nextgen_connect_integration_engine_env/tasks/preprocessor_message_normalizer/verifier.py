#!/usr/bin/env python3
"""
Verifier for preprocessor_message_normalizer task.
"""

import json
import tempfile
import os
import re

def verify_preprocessor_message_normalizer(traj, env_info, task_info):
    """
    Verify that the agent created a channel to normalize HL7 messages.
    
    Criteria:
    1. Channel 'Pharmacy_Message_Normalizer' exists (15 pts)
    2. Preprocessor script handles LF -> CR replacement (15 pts)
    3. Preprocessor script handles whitespace trimming (15 pts)
    4. Channel is deployed/started (10 pts)
    5. Message was processed (received count > 0) (15 pts)
    6. Output file was created (15 pts)
    7. Output file content is strictly valid (CR only, no trailing space) (15 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Channel Exists
    if result.get('channel_exists', False):
        score += 15
        feedback_parts.append("Channel 'Pharmacy_Message_Normalizer' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Channel 'Pharmacy_Message_Normalizer' not found."}

    # 2 & 3. Analyze Preprocessor Script
    script = result.get('preprocessor_script', '')
    if not script or script.strip() == "return message;":
        feedback_parts.append("Preprocessor script is empty or default.")
    else:
        # Check LF -> CR
        # Regex looks for variations of replace('\n', '\r') or regex /\n/g
        if re.search(r"replace.*\\n.*\\r", script, re.IGNORECASE) or \
           re.search(r"replace.*10.*13", script) or \
           re.search(r"\\x0a.*\\x0d", script, re.IGNORECASE):
            score += 15
            feedback_parts.append("Script contains LF->CR replacement logic.")
        else:
            feedback_parts.append("Script missing LF->CR replacement logic.")

        # Check Trimming
        # Regex looks for trim(), replace trailing spaces, etc.
        if re.search(r"\.trim\(\)", script) or \
           re.search(r"replace.*\\s\+\$", script) or \
           re.search(r"replace.*\\s\+\\r", script):
            score += 15
            feedback_parts.append("Script contains whitespace trimming logic.")
        else:
            feedback_parts.append("Script missing whitespace trimming logic.")

    # 4. Channel Status
    status = str(result.get('channel_status', '')).upper()
    if status in ['STARTED', 'DEPLOYED', 'RUNNING']:
        score += 10
        feedback_parts.append(f"Channel is {status}.")
    else:
        feedback_parts.append(f"Channel status is {status} (expected STARTED).")

    # 5. Message Processing
    received = result.get('received_count', 0)
    if received > 0:
        score += 15
        feedback_parts.append(f"Channel processed {received} message(s).")
    else:
        feedback_parts.append("No messages processed.")

    # 6. Output File Existence
    out_count = result.get('output_file_count', 0)
    if out_count > 0:
        score += 15
        feedback_parts.append("Output file created.")
    else:
        feedback_parts.append("No output file found in /tmp/normalized_messages/.")

    # 7. Output Content Validation
    if result.get('output_content_valid', False):
        score += 15
        feedback_parts.append("Output file content is valid (Correct delimiters, no trailing space).")
    else:
        # Provide specific hints on what failed
        if out_count > 0:
            if not result.get('has_cr', False):
                feedback_parts.append("Output file invalid: Missing CR delimiters.")
            if not result.get('no_trailing_space', False):
                feedback_parts.append("Output file invalid: Contains trailing whitespace.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }