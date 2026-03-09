#!/usr/bin/env python3
"""
Verifier for editcap_capture_manipulation task.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_editcap_capture_manipulation(traj, env_info, task_info):
    """
    Verify the 5 editcap operations and the JSON report.
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

    score = 0
    feedback_parts = []
    
    gt = result.get('ground_truth', {})
    files = result.get('files', {})
    report = result.get('report', {})
    
    # --- Check 1: First 100 Packets (15 pts) ---
    f100 = files.get('first_100', {})
    if f100.get('exists') and f100.get('created_during_task'):
        count = f100.get('packet_count', 0)
        ts = float(f100.get('first_timestamp', 0))
        gt_ts = float(gt.get('first_timestamp', 0))
        
        if count == 100:
            # Check if it starts at the right place (same start as original)
            if abs(ts - gt_ts) < 0.001:
                score += 15
                feedback_parts.append("first_100: Correct")
            else:
                score += 10
                feedback_parts.append("first_100: Count correct but timestamps differ")
        else:
            feedback_parts.append(f"first_100: Wrong count ({count})")
    else:
        feedback_parts.append("first_100: Missing or old")

    # --- Check 2: Range 50-150 (15 pts) ---
    frange = files.get('range_50_150', {})
    if frange.get('exists') and frange.get('created_during_task'):
        # Range 50-150 inclusive is 101 packets
        count = frange.get('packet_count', 0)
        ts = float(frange.get('first_timestamp', 0))
        gt_ts = float(gt.get('packet_50_timestamp', 0))
        
        if count == 101:
            if abs(ts - gt_ts) < 0.001:
                score += 15
                feedback_parts.append("range_50_150: Correct")
            else:
                score += 10
                feedback_parts.append("range_50_150: Count correct but wrong start packet")
        else:
            feedback_parts.append(f"range_50_150: Wrong count ({count} != 101)")
    else:
        feedback_parts.append("range_50_150: Missing or old")

    # --- Check 3: Converted to pcap (15 pts) ---
    fconv = files.get('converted', {})
    if fconv.get('exists') and fconv.get('created_during_task'):
        fmt = fconv.get('format', '').lower()
        count = fconv.get('packet_count', 0)
        orig_count = gt.get('original_count', 0)
        
        # Format string usually contains "Wireshark/tcpdump" or "pcap" but NOT "pcapng"
        is_pcap = "pcap" in fmt and "pcapng" not in fmt
        # capinfos output for pcap often says "Wireshark/tcpdump..."
        if "tcpdump" in fmt: is_pcap = True
        
        if is_pcap and count == orig_count:
            score += 15
            feedback_parts.append("converted: Correct")
        elif is_pcap:
            score += 10
            feedback_parts.append(f"converted: Correct format but wrong count ({count})")
        else:
            feedback_parts.append(f"converted: Wrong format ({fmt})")
    else:
        feedback_parts.append("converted: Missing or old")

    # --- Check 4: Deduped (15 pts) ---
    fdedup = files.get('deduped', {})
    if fdedup.get('exists') and fdedup.get('created_during_task'):
        count = fdedup.get('packet_count', 0)
        gt_dedup = gt.get('dedup_count', 0)
        
        # Allow +/- 1 packet tolerance for different editcap versions
        if abs(count - gt_dedup) <= 1:
            score += 15
            feedback_parts.append("deduped: Correct")
        else:
            feedback_parts.append(f"deduped: Wrong count ({count} vs {gt_dedup})")
    else:
        feedback_parts.append("deduped: Missing or old")

    # --- Check 5: Time Shifted (15 pts) ---
    fshift = files.get('timeshifted', {})
    if fshift.get('exists') and fshift.get('created_during_task'):
        count = fshift.get('packet_count', 0)
        ts = float(fshift.get('first_timestamp', 0))
        gt_ts = float(gt.get('first_timestamp', 0))
        expected_ts = gt_ts + 3600.0
        
        if count == gt.get('original_count', 0):
            if abs(ts - expected_ts) < 1.0: # Allow small float tolerance
                score += 15
                feedback_parts.append("timeshifted: Correct")
            else:
                feedback_parts.append(f"timeshifted: Wrong shift (diff {ts - gt_ts})")
        else:
            feedback_parts.append("timeshifted: Packet count changed")
    else:
        feedback_parts.append("timeshifted: Missing or old")

    # --- Check 6: Report Existence (5 pts) ---
    if report.get('exists'):
        score += 5
        feedback_parts.append("report: Exists")
        
        # --- Check 7: Report Accuracy (20 pts) ---
        content = report.get('content', {})
        report_score = 0
        
        # Check specific fields
        # Original count
        if content.get('original_packet_count') == gt.get('original_count'): report_score += 2
        
        # First 100 count
        if content.get('first_100_packet_count') == 100: report_score += 2
        
        # Time shift seconds
        if content.get('time_shift_seconds') == 3600: report_score += 3
        
        # Duplicates removed math
        user_dups = content.get('duplicates_removed', 0)
        calc_dups = gt.get('original_count', 0) - gt.get('dedup_count', 0)
        if abs(user_dups - calc_dups) <= 1: report_score += 3
        
        # Format string check
        if "pcap" in str(content.get('converted_format', '')).lower(): report_score += 2
        
        # Dedup count
        if abs(content.get('deduped_packet_count', 0) - gt.get('dedup_count', 0)) <= 1: report_score += 3
        
        # Converted count
        if content.get('converted_packet_count') == gt.get('original_count'): report_score += 3
        
        # Range count
        if content.get('range_50_150_packet_count') == 101: report_score += 2
        
        score += report_score
        feedback_parts.append(f"report_accuracy: +{report_score}/20")
    else:
        feedback_parts.append("report: Missing")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }