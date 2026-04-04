#!/usr/bin/env python3
"""
Verifier for tcp_retransmission_analysis task.

SCORING CRITERIA:
1. Exported file exists and created during task (10 pts)
2. Exported file is valid PCAP (10 pts)
3. Exported packet count matches ground truth (20 pts)
4. Exported content is pure retransmissions (no extra packets) (20 pts)
5. Report file exists (10 pts)
6. Report count correct (15 pts)
7. Report IP correct (15 pts)

Total: 100 pts
Pass Threshold: 60 pts
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tcp_retransmission_analysis(traj, env_info, task_info):
    """
    Verify the TCP retransmission analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    # Extract data
    gt = result.get('ground_truth', {})
    export = result.get('exported_file', {})
    report = result.get('report_file', {})
    start_time = result.get('task_start_timestamp', 0)

    score = 0
    feedback_parts = []
    
    # 1. Exported file exists and created during task (10 pts)
    if export.get('exists') and export.get('mod_timestamp', 0) > start_time:
        score += 10
        feedback_parts.append("Exported file created.")
    elif export.get('exists'):
        feedback_parts.append("Exported file exists but timestamp is old (reused file?).")
    else:
        feedback_parts.append("Exported file not found.")

    # 2. Exported file is valid PCAP (10 pts)
    if export.get('valid_pcap'):
        score += 10
        feedback_parts.append("Exported file is valid PCAP.")
    else:
        if export.get('exists'):
            feedback_parts.append("Exported file is NOT a valid PCAP (maybe empty or text?).")
    
    # 3. Exported packet count matches ground truth (20 pts)
    gt_count = gt.get('count', 0)
    user_count = export.get('packet_count', 0)
    
    if export.get('valid_pcap'):
        diff = abs(user_count - gt_count)
        if diff <= 2:
            score += 20
            feedback_parts.append(f"Packet count correct ({user_count}).")
        elif diff <= 5:
            score += 10
            feedback_parts.append(f"Packet count close ({user_count}, expected {gt_count}).")
        else:
            feedback_parts.append(f"Packet count mismatch ({user_count}, expected {gt_count}).")
            
        # Check if they exported ALL packets instead of just filtered
        gt_total = gt.get('total_original_packets', 999999)
        if user_count >= gt_total and gt_total > 0:
            feedback_parts.append("WARNING: You appear to have exported ALL packets, not just the filtered ones.")
            # Penalize heavily if they exported everything
            if score >= 10: score -= 10

    # 4. Content purity (20 pts)
    # Check if the exported file contains ONLY retransmissions
    non_retrans = export.get('non_retrans_count', 0)
    if export.get('valid_pcap') and user_count > 0:
        if non_retrans == 0:
            score += 20
            feedback_parts.append("Exported file contains only retransmissions.")
        elif non_retrans < 5:
            score += 10
            feedback_parts.append(f"Exported file contains mostly retransmissions ({non_retrans} incorrect packets).")
        else:
            feedback_parts.append(f"Exported file contains {non_retrans} non-retransmission packets.")

    # 5. Report file exists (10 pts)
    if report.get('exists') and report.get('mod_timestamp', 0) > start_time:
        score += 10
        feedback_parts.append("Report file created.")
    elif report.get('exists'):
        feedback_parts.append("Report file exists but timestamp is old.")
    else:
        feedback_parts.append("Report file not found.")

    # 6. Report count correct (15 pts)
    try:
        parsed_count = int(report.get('parsed_count', -1))
        if parsed_count != -1:
            if abs(parsed_count - gt_count) <= 2:
                score += 15
                feedback_parts.append("Reported count correct.")
            else:
                feedback_parts.append(f"Reported count incorrect ({parsed_count} vs {gt_count}).")
        else:
             feedback_parts.append("Could not parse count from report.")
    except:
        feedback_parts.append("Could not parse count from report.")

    # 7. Report IP correct (15 pts)
    parsed_ip = report.get('parsed_ip', "").strip()
    gt_ip = gt.get('top_ip', "").strip()
    
    if parsed_ip and gt_ip:
        if parsed_ip == gt_ip:
            score += 15
            feedback_parts.append("Reported IP correct.")
        else:
            feedback_parts.append(f"Reported IP incorrect ({parsed_ip} vs {gt_ip}).")
    else:
        feedback_parts.append("Could not parse IP from report.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }