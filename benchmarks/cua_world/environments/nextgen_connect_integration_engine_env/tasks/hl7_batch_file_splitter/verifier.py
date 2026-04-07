#!/usr/bin/env python3
"""
Verifier for HL7 Batch File Splitter task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_batch_splitter(traj, env_info, task_info):
    """
    Verify the agent created a channel that splits HL7 batch files.
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
            
    # Extract Data
    channel_info = result.get("channel_info", {})
    output_count = result.get("output_file_count", 0)
    valid_count = result.get("valid_message_file_count", 0)
    found_ids_str = result.get("found_message_ids", "")
    
    score = 0
    feedback_parts = []
    
    # Criteria 1: Channel Creation & Config (30 pts)
    if channel_info.get("channel_found"):
        score += 10
        feedback_parts.append("Channel found")
        
        if "File Reader" in channel_info.get("source_type", "") or "File" in channel_info.get("source_type", ""):
            score += 10
            feedback_parts.append("Source is File Reader")
        
        if "File Writer" in channel_info.get("destination_type", "") or "File" in channel_info.get("destination_type", ""):
            score += 10
            feedback_parts.append("Destination is File Writer")
    else:
        feedback_parts.append("No matching channel found")

    # Criteria 2: Channel State (10 pts)
    state = channel_info.get("channel_state", "UNKNOWN")
    if state in ["STARTED", "DEPLOYED", "POLLING"]:
        score += 10
        feedback_parts.append(f"Channel is {state}")
    else:
        feedback_parts.append(f"Channel state is {state} (expected STARTED/DEPLOYED)")
        
    # Criteria 3: Output Files Exist (20 pts)
    if output_count == 5:
        score += 20
        feedback_parts.append("Correct number of output files (5)")
    elif output_count > 0:
        score += 10
        feedback_parts.append(f"Partial output files found: {output_count} (expected 5)")
    else:
        feedback_parts.append("No output files found")
        
    # Criteria 4: Correct Split (Content Validation) (20 pts)
    # Each file should contain exactly 1 MSH segment
    if valid_count == 5:
        score += 20
        feedback_parts.append("All files contain valid single messages")
    elif valid_count > 0:
        score += 10
        feedback_parts.append(f"{valid_count} valid message files found")
        
    # Criteria 5: Message Integrity (IDs) (20 pts)
    expected_ids = ["MSG001", "MSG002", "MSG003", "MSG004", "MSG005"]
    found_ids_count = 0
    for eid in expected_ids:
        if eid in found_ids_str:
            found_ids_count += 1
            
    if found_ids_count == 5:
        score += 20
        feedback_parts.append("All specific message IDs found in output")
    else:
        score += int((found_ids_count / 5) * 20)
        feedback_parts.append(f"Found {found_ids_count}/5 message IDs")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }