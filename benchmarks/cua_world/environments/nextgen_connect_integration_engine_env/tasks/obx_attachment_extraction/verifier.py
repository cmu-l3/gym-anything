#!/usr/bin/env python3
"""
Verifier for obx_attachment_extraction task.
Checks if the channel exists, is configured correctly, and produces the expected PDF output.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_obx_extraction(traj, env_info, task_info):
    """
    Verifies that the agent created a channel that extracts a PDF from an HL7 message.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_mrn = metadata.get('expected_mrn', 'PAT78432')
    expected_port = str(metadata.get('port', 6661))

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Channel Configuration (40 points)
    if result.get('channel_found'):
        score += 15
        feedback_parts.append("Channel 'Lab_Report_Extractor' found.")
        
        # Check Port
        actual_port = str(result.get('listener_port', ''))
        if actual_port == expected_port:
            score += 15
            feedback_parts.append(f"Channel listening on correct port {expected_port}.")
        else:
            feedback_parts.append(f"Channel listening on wrong port (Expected: {expected_port}, Found: {actual_port}).")
            
        # Check Status
        status = result.get('channel_status', 'UNKNOWN')
        if status in ['STARTED', 'DEPLOYED', 'RUNNING']: # NextGen API status codes vary slightly by version
            score += 10
            feedback_parts.append("Channel is deployed and running.")
        else:
            feedback_parts.append(f"Channel status is {status} (Expected: STARTED/DEPLOYED).")
    else:
        feedback_parts.append("Channel 'Lab_Report_Extractor' NOT found.")

    # 2. Message Processing & Output (60 points)
    # The export script sends a test message. We check if it produced a file.
    
    if result.get('messages_received', 0) > 0:
        score += 5
        feedback_parts.append("Channel received messages.")
    
    if result.get('output_file_found'):
        score += 10
        feedback_parts.append("Output PDF file found.")
        
        # Anti-gaming: Created during task?
        if result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File was created during the task window.")
        else:
            feedback_parts.append("WARNING: File timestamp is older than task start.")
            
        # Valid PDF?
        if result.get('is_valid_pdf'):
            score += 20
            feedback_parts.append("File content is a valid PDF.")
        else:
            feedback_parts.append("File content is NOT a valid PDF (decoding failed?).")
            
        # MRN in filename?
        if result.get('filename_has_mrn'):
            score += 15
            feedback_parts.append(f"Filename contains expected MRN ({expected_mrn}).")
        else:
            feedback_parts.append(f"Filename missing MRN ({expected_mrn}).")
    else:
        feedback_parts.append("No output file produced after sending test message.")

    # Pass Threshold
    passed = score >= 60 and result.get('output_file_found') and result.get('is_valid_pdf')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }