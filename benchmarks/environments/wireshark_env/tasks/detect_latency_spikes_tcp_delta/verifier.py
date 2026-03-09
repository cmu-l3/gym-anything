#!/usr/bin/env python3
"""
Verifier for detect_latency_spikes_tcp_delta task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_latency_spikes(traj, env_info, task_info):
    """
    Verifies the TCP latency analysis task.
    
    Criteria:
    1. Filtered PCAP exists and has correct packet count (30 pts)
    2. Report file exists (10 pts)
    3. Report contains correct total count (20 pts)
    4. Report contains correct worst stream index (20 pts)
    5. Report contains correct max delta (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    score = 0
    feedback = []
    
    # Ground Truths
    gt_count = result.get('gt_count', 0)
    gt_stream = str(result.get('gt_stream', ''))
    gt_max_delta = float(result.get('gt_max_delta', 0.0))
    
    # User Values
    pcap_exists = result.get('pcap_exists', False)
    pcap_count = result.get('pcap_packet_count', 0)
    report_exists = result.get('report_exists', False)
    
    user_count_str = str(result.get('user_count', ''))
    user_stream = str(result.get('user_stream', ''))
    user_delta_str = str(result.get('user_delta', ''))

    # 1. PCAP Check
    if pcap_exists:
        if pcap_count == gt_count:
            score += 30
            feedback.append(f"Exported PCAP has correct packet count ({pcap_count}).")
        elif abs(pcap_count - gt_count) <= 2:
            score += 20
            feedback.append(f"Exported PCAP count is close ({pcap_count}, expected {gt_count}).")
        else:
            score += 10 # File exists but count wrong
            feedback.append(f"Exported PCAP count mismatch ({pcap_count}, expected {gt_count}).")
    else:
        feedback.append("Exported PCAP file not found.")

    # 2. Report Exists
    if report_exists:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file not found.")

    # 3. Report Content - Count
    if user_count_str.isdigit():
        user_count = int(user_count_str)
        if user_count == gt_count:
            score += 20
            feedback.append("Reported packet count matches ground truth.")
        else:
            feedback.append(f"Reported count mismatch (User: {user_count}, GT: {gt_count}).")
    else:
        feedback.append("Could not parse packet count from report.")

    # 4. Report Content - Stream Index
    # Stream index might be exact
    if user_stream == gt_stream and user_stream != "":
        score += 20
        feedback.append(f"Reported worst stream index is correct ({user_stream}).")
    else:
        feedback.append(f"Reported stream index incorrect (User: '{user_stream}', GT: '{gt_stream}').")

    # 5. Report Content - Max Delta
    try:
        user_delta = float(user_delta_str) if user_delta_str else 0.0
        # Tolerance of 0.001s
        if abs(user_delta - gt_max_delta) < 0.001:
            score += 20
            feedback.append(f"Reported max delta is correct ({user_delta}s).")
        else:
            feedback.append(f"Reported max delta incorrect (User: {user_delta}, GT: {gt_max_delta}).")
    except ValueError:
        feedback.append("Could not parse max delta from report.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }