#!/usr/bin/env python3
"""
Verifier for identify_power_anomaly task.
Parses the agent's report file and compares it against the injected ground truth.
"""

import json
import os
import base64
import logging
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report(content_str):
    """
    Parses the report text looking for:
    peak_timestamp: <int>
    peak_value_watts: <number>
    anomaly_duration_minutes: <number>
    """
    data = {}
    
    # Regex patterns (flexible with whitespace and case)
    ts_pattern = re.search(r"peak_timestamp\s*[:=]\s*(\d+)", content_str, re.IGNORECASE)
    val_pattern = re.search(r"peak_value_watts\s*[:=]\s*([\d\.]+)", content_str, re.IGNORECASE)
    dur_pattern = re.search(r"anomaly_duration_minutes\s*[:=]\s*([\d\.]+)", content_str, re.IGNORECASE)

    if ts_pattern:
        try: data['timestamp'] = int(ts_pattern.group(1))
        except: pass
    
    if val_pattern:
        try: data['value'] = float(val_pattern.group(1))
        except: pass
        
    if dur_pattern:
        try: data['duration'] = float(dur_pattern.group(1))
        except: pass
        
    return data

def verify_identify_power_anomaly(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified the power anomaly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Decode Ground Truth
    truth_b64 = result.get('ground_truth_b64', '')
    if not truth_b64:
        return {"passed": False, "score": 0, "feedback": "Ground truth missing from environment"}
    
    try:
        truth = json.loads(base64.b64decode(truth_b64).decode('utf-8'))
    except:
        return {"passed": False, "score": 0, "feedback": "Failed to decode ground truth"}

    # 3. Decode User Report
    report_exists = result.get('report_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file /home/ga/anomaly_report.txt not found"}
    
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "Report file exists but was not created during this task session (stale data)"}

    report_content_b64 = result.get('report_content_b64', '')
    try:
        report_text = base64.b64decode(report_content_b64).decode('utf-8')
    except:
        return {"passed": False, "score": 0, "feedback": "Failed to decode report content"}

    user_data = parse_report(report_text)
    
    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Base points for creating the file correctly
    score += 10
    
    # Timestamp Check (30 pts)
    # Tolerance: +/- 10 minutes (600s) - usually it's exact, but graph hovering might be slightly off
    # Wider tolerance: +/- 30 minutes (1800s) for partial credit
    actual_ts = truth['peak_timestamp']
    user_ts = user_data.get('timestamp')
    
    if user_ts is not None:
        diff = abs(user_ts - actual_ts)
        if diff <= 600:
            score += 30
            feedback_parts.append("Timestamp accurate")
        elif diff <= 1800:
            score += 15
            feedback_parts.append(f"Timestamp slightly off ({diff}s)")
        else:
            feedback_parts.append(f"Timestamp incorrect (off by {diff}s)")
    else:
        feedback_parts.append("Timestamp not found in report")

    # Value Check (30 pts)
    # Tolerance: +/- 100 Watts (graph hover precision)
    actual_val = truth['peak_value']
    user_val = user_data.get('value')
    
    if user_val is not None:
        diff_val = abs(user_val - actual_val)
        if diff_val <= 100:
            score += 30
            feedback_parts.append("Peak value accurate")
        elif diff_val <= 500:
            score += 15
            feedback_parts.append(f"Peak value acceptable deviation ({diff_val}W)")
        else:
            feedback_parts.append(f"Peak value incorrect (off by {diff_val}W)")
    else:
        feedback_parts.append("Peak value not found in report")

    # Duration Check (30 pts)
    # Tolerance: +/- 10 mins (one interval)
    actual_dur = truth['duration_minutes']
    user_dur = user_data.get('duration')
    
    if user_dur is not None:
        diff_dur = abs(user_dur - actual_dur)
        if diff_dur <= 10:
            score += 30
            feedback_parts.append("Duration accurate")
        elif diff_dur <= 20:
            score += 15
            feedback_parts.append(f"Duration slightly off ({diff_dur}m)")
        else:
            feedback_parts.append(f"Duration incorrect (off by {diff_dur}m)")
    else:
        feedback_parts.append("Duration not found in report")

    # Final tally
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "ground_truth": truth,
            "user_data": user_data
        }
    }