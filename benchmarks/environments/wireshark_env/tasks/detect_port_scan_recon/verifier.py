#!/usr/bin/env python3
"""
Verifier for Port Scan Reconnaissance task.

Verifies:
1. Report existence and freshness.
2. Accuracy of forensic findings (Scanner IP, Target IP, Ports, etc.)
3. Evidence of Wireshark usage via VLM trajectory.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(content):
    """
    Parses the raw text content of the report into a dictionary.
    Expects format: KEY: VALUE
    """
    data = {}
    if not content:
        return data
    
    # Split by newline (the export script uses \n for newlines in JSON string)
    lines = content.split('\n')
    for line in lines:
        if ':' in line:
            key, value = line.split(':', 1)
            clean_key = key.strip().upper()
            clean_value = value.strip()
            data[clean_key] = clean_value
            
    return data

def verify_detect_port_scan_recon(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Extract Data
    ground_truth = result.get('ground_truth', {})
    report_content_raw = result.get('report_content_raw', "")
    user_data = parse_report_content(report_content_raw)
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Report File (10 pts) ---
    if result.get('report_exists') and result.get('report_created_during_task'):
        score += 10
        feedback_parts.append("Report file created successfully")
    elif result.get('report_exists'):
        score += 5
        feedback_parts.append("Report file exists but timestamp is old")
    else:
        feedback_parts.append("Report file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Scanner IP (10 pts) ---
    gt_scanner = ground_truth.get('scanner_ip', '192.168.50.10')
    user_scanner = user_data.get('SCANNER_IP', '')
    if user_scanner == gt_scanner:
        score += 10
        feedback_parts.append("Scanner IP correct")
    else:
        feedback_parts.append(f"Scanner IP incorrect (Expected {gt_scanner}, got '{user_scanner}')")

    # --- Criterion 3: Target IP (10 pts) ---
    gt_target = ground_truth.get('target_ip', '192.168.50.20')
    user_target = user_data.get('TARGET_IP', '')
    if user_target == gt_target:
        score += 10
        feedback_parts.append("Target IP correct")
    else:
        feedback_parts.append(f"Target IP incorrect (Expected {gt_target})")

    # --- Criterion 4: Scan Type (15 pts) ---
    gt_type = ground_truth.get('scan_type', 'SYN')
    user_type = user_data.get('SCAN_TYPE', '').upper()
    if gt_type in user_type:
        score += 15
        feedback_parts.append("Scan Type correct")
    else:
        feedback_parts.append(f"Scan Type incorrect (Expected {gt_type})")

    # --- Criterion 5: Total Ports Probed (10 pts) ---
    # Allow small tolerance
    try:
        gt_total = int(ground_truth.get('total_ports_probed', 0))
        user_total = int(user_data.get('TOTAL_PORTS_PROBED', 0))
        if abs(user_total - gt_total) <= 5:
            score += 10
            feedback_parts.append(f"Total ports count accurate ({user_total})")
        else:
            feedback_parts.append(f"Total ports count mismatch ({user_total} vs {gt_total})")
    except ValueError:
        feedback_parts.append("Total ports value not a valid integer")

    # --- Criterion 6: Open Ports (20 pts) ---
    # Parse list logic
    gt_open_str = str(ground_truth.get('open_ports', ''))
    user_open_str = user_data.get('OPEN_PORTS', '')
    
    # Normalize strings to sets of integers
    try:
        gt_open_set = set(int(p.strip()) for p in gt_open_str.split(',') if p.strip())
        user_open_set = set(int(p.strip()) for p in user_open_str.split(',') if p.strip())
        
        if gt_open_set == user_open_set:
            score += 20
            feedback_parts.append("Open ports identified correctly")
        elif user_open_set.issubset(gt_open_set) and len(user_open_set) > 0:
            score += 10
            feedback_parts.append("Partial open ports identified")
        else:
            feedback_parts.append(f"Open ports mismatch (Expected {gt_open_str})")
    except ValueError:
        feedback_parts.append("Open ports format error")

    # --- Criterion 7: Closed Ports Count (10 pts) ---
    try:
        gt_closed = int(ground_truth.get('closed_ports_count', 0))
        user_closed = int(user_data.get('CLOSED_PORTS_COUNT', 0))
        # Allow 10% tolerance
        tolerance = max(2, int(gt_closed * 0.1))
        if abs(user_closed - gt_closed) <= tolerance:
            score += 10
            feedback_parts.append(f"Closed ports count accurate ({user_closed})")
        else:
            feedback_parts.append(f"Closed ports count mismatch ({user_closed} vs {gt_closed})")
    except ValueError:
        feedback_parts.append("Closed ports count not a valid integer")

    # --- Criterion 8: Background Protocol (5 pts) ---
    gt_proto = ground_truth.get('background_protocol', 'HTTP')
    user_proto = user_data.get('BACKGROUND_PROTOCOL', '').upper()
    if gt_proto in user_proto:
        score += 5
        feedback_parts.append("Background protocol identified")
    else:
        feedback_parts.append("Background protocol incorrect")

    # --- Criterion 9: Wireshark usage (10 pts) ---
    if result.get('wireshark_running'):
        score += 10
        feedback_parts.append("Wireshark was running")
    else:
        feedback_parts.append("Wireshark was not running at end of task")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }