#!/usr/bin/env python3
"""
Verifier for forensic_traffic_annotation task.
Checks if the agent correctly identified the top talker stream,
annotated it, and exported it.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forensic_traffic_annotation(traj, env_info, task_info):
    """
    Verify forensic annotation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Score calculation
    score = 0
    feedback = []
    
    # 1. Output file exists and was created during task (10 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 10
        feedback.append("Output file created successfully.")
    elif result.get('output_exists'):
        # Exists but timestamp issue?
        score += 5
        feedback.append("Output file exists but timestamp check failed.")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Correct Conversation / Packet Count (30 pts)
    gt = result.get('ground_truth', {})
    target_count = gt.get('target_packet_count', 0)
    output_count = result.get('output_packet_count', 0)
    
    # Tolerance of +/- 2 packets
    if abs(output_count - target_count) <= 2:
        score += 30
        feedback.append(f"Packet count matches ground truth ({output_count}).")
    elif output_count > 0:
        # Partial credit if close (within 10%)
        if abs(output_count - target_count) < (target_count * 0.1):
            score += 15
            feedback.append(f"Packet count close to expected ({output_count} vs {target_count}).")
        else:
            feedback.append(f"Packet count incorrect ({output_count} vs {target_count}). Wrong conversation?")
    else:
        feedback.append("Output file is empty.")

    # 3. Clean Export (20 pts)
    # Should ideally contain 1 stream. 
    # Note: If exported to a new file, tshark usually sees 1 stream (index 0). 
    # If multiple streams are present, they failed to filter correctly.
    stream_count = result.get('output_stream_count', 0)
    if stream_count == 1:
        score += 20
        feedback.append("Export contains single stream (clean export).")
    elif stream_count > 1:
        feedback.append(f"Export contains {stream_count} streams. Should only contain one.")
    
    # 4. Annotations (40 pts total)
    start_cmt = result.get('first_packet_comment', '') or ""
    end_cmt = result.get('last_packet_comment', '') or ""
    
    # Start Comment (20 pts)
    if "evidence start" in start_cmt.lower():
        score += 20
        feedback.append("Start annotation correct.")
    elif start_cmt:
        score += 5
        feedback.append(f"Start annotation present but incorrect: '{start_cmt}'")
    else:
        feedback.append("Start annotation missing.")
        
    # End Comment (20 pts)
    if "evidence end" in end_cmt.lower():
        score += 20
        feedback.append("End annotation correct.")
    elif end_cmt:
        score += 5
        feedback.append(f"End annotation present but incorrect: '{end_cmt}'")
    else:
        feedback.append("End annotation missing.")

    # Pass threshold
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }