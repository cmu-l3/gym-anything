#!/usr/bin/env python3
"""
Verifier for correct_timestamp_offset task.
Checks if the agent correctly time-shifted the capture file by +3600 seconds.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_timestamp_shift(traj, env_info, task_info):
    """
    Verify the timestamp shift task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Config
    target_shift = task_info.get('metadata', {}).get('target_shift_seconds', 3600)
    tolerance = task_info.get('metadata', {}).get('tolerance_seconds', 1.0)
    
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (30 pts)
    if result.get('output_exists') and result.get('is_valid_pcap'):
        score += 30
        feedback_parts.append("Valid output file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file missing or invalid."}

    # 2. Anti-gaming check (10 pts)
    if result.get('file_created_during_task'):
        score += 10
    else:
        feedback_parts.append("Warning: Output file timestamp mismatch (pre-dated task).")

    # 3. Data Integrity (20 pts)
    metrics = result.get('metrics', {})
    orig_count = metrics.get('original_packet_count', 0)
    out_count = metrics.get('output_packet_count', 0)
    
    if orig_count > 0 and out_count == orig_count:
        score += 20
        feedback_parts.append(f"Packet count preserved ({out_count}).")
    else:
        feedback_parts.append(f"Packet count mismatch (Original: {orig_count}, Output: {out_count}).")

    # 4. Timestamp Shift Accuracy (40 pts)
    orig_time = metrics.get('original_start_time', 0.0)
    out_time = metrics.get('output_start_time', 0.0)
    
    actual_shift = out_time - orig_time
    diff = abs(actual_shift - target_shift)
    
    if diff <= tolerance:
        score += 40
        feedback_parts.append(f"Timestamp shift correct (+{actual_shift:.2f}s).")
    elif diff <= 5.0:
        score += 20
        feedback_parts.append(f"Timestamp shift slightly off (+{actual_shift:.2f}s, expected {target_shift}s).")
    else:
        feedback_parts.append(f"Timestamp shift incorrect (+{actual_shift:.2f}s, expected {target_shift}s).")

    # Final decision
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }