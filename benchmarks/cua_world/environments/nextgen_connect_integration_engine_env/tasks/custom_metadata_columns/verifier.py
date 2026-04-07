#!/usr/bin/env python3
"""
Verifier for custom_metadata_columns task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_metadata_columns(traj, env_info, task_info):
    """
    Verify that the channel was created with correct metadata columns and processing logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_msg1_mrn = metadata.get('msg1_mrn', 'MRN78432')
    expected_msg2_mrn = metadata.get('msg2_mrn', 'MRN91205')

    # Copy result file
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

    # 1. Channel Existence (10 pts)
    if result.get('channel_exists', False):
        score += 10
        feedback_parts.append("Channel 'ADT_Metadata_Tracker' exists.")
    else:
        feedback_parts.append("Channel 'ADT_Metadata_Tracker' NOT found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_parts)}

    # 2. Metadata Columns Defined (20 pts)
    if result.get('columns_defined', False):
        score += 20
        feedback_parts.append("Custom metadata columns defined correctly.")
    else:
        feedback_parts.append("Custom metadata columns missing or incorrect names.")

    # 3. Transformer Logic Exists (15 pts)
    if result.get('transformer_steps_exist', False):
        score += 15
        feedback_parts.append("Source transformer steps detected.")
    else:
        feedback_parts.append("No source transformer steps detected.")

    # 4. Channel Deployment (10 pts)
    status = result.get('channel_status', 'UNKNOWN')
    if status in ['STARTED', 'DEPLOYED', 'RUNNING']:
        score += 10
        feedback_parts.append(f"Channel is {status}.")
    else:
        feedback_parts.append(f"Channel status is {status} (expected STARTED).")

    # 5. Message Processing Counts (10 pts)
    msg_count = result.get('message_count', 0)
    if msg_count >= 2:
        score += 10
        feedback_parts.append(f"Processed {msg_count} messages.")
    else:
        feedback_parts.append(f"Processed only {msg_count} messages (expected >= 2).")

    # 6. Error Free (5 pts)
    err_count = result.get('error_count', 0)
    if err_count == 0 and msg_count > 0:
        score += 5
        feedback_parts.append("No processing errors.")
    elif err_count > 0:
        feedback_parts.append(f"Channel reported {err_count} errors.")

    # 7. Metadata Extraction Verification (25 pts total)
    # We look at the actual extracted values from the processed messages
    msgs_meta = result.get('metadata_verification', [])
    
    found_msg1 = False
    found_msg2 = False
    
    for m in msgs_meta:
        mrn = m.get('PatientMRN', '')
        name = m.get('PatientName', '')
        evt = m.get('EventType', '')
        
        # Check for Message 1 characteristics
        if expected_msg1_mrn in mrn:
            if 'JOHNSON' in name and 'A01' in evt:
                found_msg1 = True
        
        # Check for Message 2 characteristics
        if expected_msg2_mrn in mrn:
            if 'MARTINEZ' in name and 'A04' in evt:
                found_msg2 = True

    if found_msg1:
        score += 12
        feedback_parts.append("Metadata correctly extracted for ADT^A01 message.")
    else:
        feedback_parts.append("Failed to verify metadata for ADT^A01 message.")

    if found_msg2:
        score += 13
        feedback_parts.append("Metadata correctly extracted for ADT^A04 message.")
    else:
        feedback_parts.append("Failed to verify metadata for ADT^A04 message.")

    # 8. File Output (5 pts)
    if result.get('file_output_count', 0) >= 2:
        score += 5
        feedback_parts.append("Output files created.")
    else:
        feedback_parts.append("Output files missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }