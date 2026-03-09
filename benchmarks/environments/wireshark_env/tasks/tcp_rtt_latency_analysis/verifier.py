#!/usr/bin/env python3
"""
Verifier for TCP RTT Latency Analysis Task.
Checks:
1. Accuracy of reported latency statistics.
2. Correctness of exported stream pcap.
3. Wireshark configuration changes (custom columns).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tcp_rtt_latency_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    score = 0
    feedback = []

    # 1. Report Existence and Accuracy (40 pts)
    report = result.get('user_report', {})
    gt = result.get('ground_truth', {})

    if report.get('exists'):
        score += 10
        feedback.append("Report file created.")
        
        # Check Packet Number
        if str(report.get('packet')) == str(gt.get('packet')):
            score += 10
            feedback.append("Correct max RTT packet identified.")
        else:
            feedback.append(f"Wrong packet number (expected {gt.get('packet')}, got {report.get('packet')}).")

        # Check Stream Index
        if str(report.get('stream')) == str(gt.get('stream')):
            score += 10
            feedback.append("Correct stream index identified.")
        else:
            feedback.append(f"Wrong stream index (expected {gt.get('stream')}, got {report.get('stream')}).")

        # Check RTT Value (Tolerance 0.001)
        try:
            r_val = float(report.get('rtt', 0))
            g_val = float(gt.get('rtt', 0))
            if abs(r_val - g_val) < 0.001:
                score += 10
                feedback.append("Correct RTT value reported.")
            else:
                feedback.append(f"RTT value inaccurate (expected ~{g_val}, got {r_val}).")
        except ValueError:
            feedback.append("RTT value is not a valid number.")

    else:
        feedback.append("Report file NOT found.")

    # 2. Export File Verification (40 pts)
    exp = result.get('export_file', {})
    if exp.get('exists'):
        score += 10
        feedback.append("Exported PCAP exists.")
        
        if exp.get('correct_content'):
            score += 15
            feedback.append("Exported file contains the target stream traffic.")
        else:
            feedback.append("Exported file does not match target stream IPs.")
            
        if exp.get('is_single_stream'):
            score += 15
            feedback.append("Exported file correctly isolated to a single stream.")
        else:
            feedback.append("Exported file contains multiple streams (improper filtering).")
    else:
        feedback.append("Exported PCAP file NOT found.")

    # 3. UI Configuration (20 pts)
    conf = result.get('config', {})
    if conf.get('has_rtt_column'):
        score += 10
        feedback.append("Custom RTT column added to Wireshark.")
    else:
        feedback.append("RTT column not found in configuration.")

    if conf.get('has_stream_column'):
        score += 10
        feedback.append("Custom Stream column added to Wireshark.")
    else:
        feedback.append("Stream column not found in configuration.")

    # Final Calculation
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }