#!/usr/bin/env python3
"""
Verifier for packet_size_distribution_analysis task.

Criteria:
1. Report file exists and created during task (5 pts)
2. Report follows specified format (10 pts)
3. Statistics accuracy (80 pts total):
   - Total count (15 pts)
   - Min/Max size (5 pts each)
   - Avg size (10 pts)
   - Bucket counts (30 pts, 5 per bucket)
   - Bucket percentages (10 pts)
   - Dominant bucket (5 pts)
4. VLM Trajectory Verification (5 pts)
"""

import json
import base64
import re
import os
import tempfile
import logging
from typing import Dict, Any, Optional

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_packet_size_distribution_analysis(traj, env_info, task_info):
    """
    Main verification entry point.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Decode Content
    score = 0
    feedback_log = []
    
    # Decode Ground Truth
    try:
        gt_b64 = result_data.get("ground_truth_b64", "")
        if not gt_b64:
            return {"passed": False, "score": 0, "feedback": "System Error: Ground truth not found"}
        ground_truth = json.loads(base64.b64decode(gt_b64).decode('utf-8'))
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System Error: Failed to parse ground truth: {e}"}

    # Decode User Report
    report_text = ""
    file_exists = result_data.get("file_exists", False)
    file_fresh = result_data.get("file_created_during_task", False)
    
    if file_exists and file_fresh:
        score += 5
        feedback_log.append("[PASS] Report file created during task (+5)")
        try:
            report_b64 = result_data.get("report_content_b64", "")
            report_text = base64.b64decode(report_b64).decode('utf-8')
        except:
            feedback_log.append("[FAIL] Could not decode report file")
    elif file_exists:
        feedback_log.append("[FAIL] Report file exists but was not created during this session (Anti-gaming)")
    else:
        feedback_log.append("[FAIL] Report file not found")

    # If no report to analyze, return early
    if not report_text:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "\n".join(feedback_log)
        }

    # 3. Verify Format (10 pts)
    # Check for required headers
    required_headers = [
        "Packet Size Distribution Report", 
        "Capture File", 
        "Size Bucket Distribution", 
        "Dominant Bucket"
    ]
    headers_found = all(h in report_text for h in required_headers)
    if headers_found:
        score += 10
        feedback_log.append("[PASS] Report format headers correct (+10)")
    else:
        feedback_log.append("[FAIL] Report missing required headers")

    # 4. Data Extraction & Verification
    
    # Helper for extraction
    def extract_val(pattern, text, type_conv=int):
        m = re.search(pattern, text, re.IGNORECASE)
        if m:
            try:
                return type_conv(m.group(1))
            except:
                return None
        return None

    # Total Packets (15 pts)
    total_val = extract_val(r'Total Packets:\s*(\d+)', report_text)
    if total_val == ground_truth['total']:
        score += 15
        feedback_log.append(f"[PASS] Total packets match: {total_val} (+15)")
    else:
        feedback_log.append(f"[FAIL] Total packets mismatch: Found {total_val}, Expected {ground_truth['total']}")

    # Min Size (5 pts)
    min_val = extract_val(r'Min Size:\s*(\d+)', report_text)
    if min_val == ground_truth['min']:
        score += 5
        feedback_log.append(f"[PASS] Min size matches: {min_val} (+5)")
    else:
        feedback_log.append(f"[FAIL] Min size mismatch: Found {min_val}, Expected {ground_truth['min']}")

    # Max Size (5 pts)
    max_val = extract_val(r'Max Size:\s*(\d+)', report_text)
    if max_val == ground_truth['max']:
        score += 5
        feedback_log.append(f"[PASS] Max size matches: {max_val} (+5)")
    else:
        feedback_log.append(f"[FAIL] Max size mismatch: Found {max_val}, Expected {ground_truth['max']}")

    # Avg Size (10 pts) - Tolerance +/- 2
    avg_val = extract_val(r'Avg Size:\s*(\d+)', report_text)
    if avg_val is not None and abs(avg_val - ground_truth['avg']) <= 2:
        score += 10
        feedback_log.append(f"[PASS] Avg size accurate: {avg_val} (Target: {ground_truth['avg']}) (+10)")
    else:
        feedback_log.append(f"[FAIL] Avg size incorrect: Found {avg_val}, Expected {ground_truth['avg']}")

    # Bucket Analysis (30 pts counts + 10 pts percents)
    buckets = ["0-79", "80-159", "160-319", "320-639", "640-1279", "1280-2559"]
    correct_buckets = 0
    correct_pcts = 0

    for b in buckets:
        # Regex to find: "0-79: 1234 packets (10.5%)"
        # Be flexible with whitespace
        regex = re.escape(b) + r':\s*(\d+)\s*packets\s*\(\s*([0-9.]+)\s*%\s*\)'
        m = re.search(regex, report_text)
        
        gt_count = ground_truth['buckets'][b]['count']
        gt_pct = ground_truth['buckets'][b]['percent']
        
        if m:
            user_count = int(m.group(1))
            user_pct = float(m.group(2))
            
            # Count check (+/- 1 tolerance)
            if abs(user_count - gt_count) <= 1:
                score += 5
                correct_buckets += 1
                feedback_log.append(f"  - Bucket {b} count correct (+5)")
            else:
                feedback_log.append(f"  - Bucket {b} count fail (Got {user_count}, Expected {gt_count})")
            
            # Percent check (+/- 0.5% tolerance)
            if abs(user_pct - gt_pct) <= 0.5:
                correct_pcts += 1
        else:
            feedback_log.append(f"  - Bucket {b} not found in report")

    # Percentages Bonus (Need 5/6 correct for 10 pts)
    if correct_pcts >= 5:
        score += 10
        feedback_log.append(f"[PASS] Bucket percentages accurate ({correct_pcts}/6) (+10)")
    else:
        feedback_log.append(f"[FAIL] Bucket percentages inaccurate ({correct_pcts}/6 correct)")

    # Dominant Bucket (5 pts)
    # Check if correct bucket string appears in the relevant section
    dom_section_match = re.search(r'Dominant Bucket ===\s*(.*)', report_text, re.DOTALL)
    if dom_section_match:
        dom_content = dom_section_match.group(1)
        if ground_truth['dominant_bucket'] in dom_content:
            score += 5
            feedback_log.append(f"[PASS] Dominant bucket identified correctly (+5)")
        else:
            feedback_log.append(f"[FAIL] Dominant bucket mismatch. Expected {ground_truth['dominant_bucket']}")
    else:
        feedback_log.append("[FAIL] Dominant bucket section empty/missing")

    # 5. VLM / App Usage Verification (5 pts)
    # Check if app was running at end of task
    if result_data.get("app_running", False):
        score += 5
        feedback_log.append("[PASS] Wireshark was open at task end (+5)")
    else:
        feedback_log.append("[WARN] Wireshark was closed at task end")
        # Could attempt VLM trajectory check here if framework supports it
        # to confirm it WAS open during the task.
        # For this implementation, we'll check app_running status.

    passed = (score >= 60) and (total_val == ground_truth['total'])
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_log)
    }