#!/usr/bin/env python3
"""
Verifier for configure_strict_capture_filter task.

Critera:
1. Output file exists and was created during task.
2. File contains sufficient ICMP packets (>= 10).
3. File contains ZERO non-ICMP packets (strict Capture Filter check).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_strict_capture_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    min_icmp = metadata.get('min_icmp_packets', 10)
    
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

    score = 0
    feedback_parts = []
    
    # 1. File Existence and Timestamp (20 pts)
    file_exists = result.get('file_exists', False)
    file_fresh = result.get('file_created_during_task', False)
    
    if file_exists and file_fresh:
        score += 20
        feedback_parts.append("Capture file created successfully")
    elif file_exists:
        score += 10
        feedback_parts.append("Capture file exists but timestamp is old (reused?)")
    else:
        feedback_parts.append("Capture file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Target Traffic - ICMP Count (30 pts)
    icmp_count = result.get('icmp_packets', 0)
    if icmp_count >= min_icmp:
        score += 30
        feedback_parts.append(f"Captured {icmp_count} ICMP packets (Target met)")
    elif icmp_count > 0:
        partial = int(30 * (icmp_count / min_icmp))
        score += partial
        feedback_parts.append(f"Captured only {icmp_count} ICMP packets (Target: {min_icmp})")
    else:
        feedback_parts.append("No ICMP packets found in capture")

    # 3. Noise Rejection - Non-ICMP Count (50 pts)
    # This is the critical test for Capture Filter vs Display Filter
    # If they used Display Filter, the file will contain the background noise packets
    non_icmp_count = result.get('non_icmp_packets', 0)
    
    if non_icmp_count == 0:
        score += 50
        feedback_parts.append("Perfect noise rejection (0 non-ICMP packets)")
    else:
        feedback_parts.append(f"Failed noise rejection: Found {non_icmp_count} non-ICMP packets. (Did you use a Display Filter instead of a Capture Filter?)")
        # Strict penalty: if noise is high, they definitely failed the core concept
        if non_icmp_count > 5:
            score = min(score, 40) # Cap score if they failed the main objective

    passed = score >= 90  # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }