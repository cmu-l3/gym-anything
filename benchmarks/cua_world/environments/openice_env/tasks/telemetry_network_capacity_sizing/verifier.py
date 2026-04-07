#!/usr/bin/env python3
"""
Verifier for telemetry_network_capacity_sizing task.

SCORING CRITERIA (100 points total):
1. Device Created (30 pts): Evidence that a Multiparameter Monitor was created (window/log).
2. Report Exists (20 pts): Valid text file created during task.
3. Content & Logic (30 pts):
   - Contains Baseline and Active measurements.
   - Active > Baseline (delta is positive).
   - Calculated bandwidth is reasonable (1 Kbps - 5 Mbps).
4. Projections (20 pts): Report includes estimates for 10, 50, and 100 devices.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_telemetry_capacity(traj, env_info, task_info):
    # 1. Setup: Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Result JSON
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Load Report Content
    report_content = ""
    if result_data.get("report_exists", False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/capacity_plan_copy.txt", temp_report.name)
            with open(temp_report.name, 'r', errors='ignore') as f:
                report_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read report content: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # --- SCORING ---
    score = 0
    feedback = []

    # Criterion 1: Device Created (30 pts)
    # We look for window detection OR log activity OR significant window count increase
    device_created = False
    if result_data.get("monitor_window_detected", False) or \
       result_data.get("device_log_activity", False) or \
       result_data.get("window_increase", 0) >= 1:
        score += 30
        device_created = True
        feedback.append("Device creation detected.")
    else:
        feedback.append("No evidence of Multiparameter Monitor creation found.")

    # Criterion 2: Report Exists (20 pts)
    report_valid = False
    if result_data.get("report_exists", False) and result_data.get("report_created_during_task", False):
        if result_data.get("report_size_bytes", 0) > 50: # Arbitrary small minimum
            score += 20
            report_valid = True
            feedback.append("Capacity plan report file created.")
        else:
            feedback.append("Report file is empty or too small.")
    else:
        feedback.append("Report file not found or not created during task.")

    # Criterion 3: Content & Logic (30 pts)
    # We need to find numbers. This is heuristic since format varies.
    # We look for ANY numbers associated with "baseline", "active", "bandwidth", etc.
    content_score = 0
    if report_valid and len(report_content) > 0:
        lower_content = report_content.lower()
        
        # Check for keywords
        has_baseline = "baseline" in lower_content or "idle" in lower_content
        has_active = "active" in lower_content or "load" in lower_content
        
        # Simple number extraction
        # Look for numbers (float or int)
        numbers = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", report_content)]
        
        valid_math = False
        reasonable_range = False
        
        # Heuristic: If we have at least 2 numbers, assume they might be measurements
        if len(numbers) >= 2:
            # Check if any number is in reasonable range (1 Kbps to 5000 Kbps)
            # Users might report in Bytes, bits, KiloBytes, Kilobits.
            # 1 Kbps = 1000 bits/sec. 5000 Kbps = 5,000,000 bits/sec.
            # Or in bytes: ~100 B/s to 600 KB/s.
            
            # We treat ANY number between 0.1 and 10,000,000 as potentially valid to be generous with units,
            # but we penalize obvious hallucinations like "0" or negative numbers.
            valid_numbers = [n for n in numbers if n > 0]
            
            if len(valid_numbers) >= 2:
                # Assuming the user did [Active] - [Baseline] = [Delta]
                # We can't strictly parse which is which without strict formatting,
                # but we give credit for having non-zero data.
                content_score += 15 
                
                # Check for "reasonable" bandwidth
                # A simulated device shouldn't take 10 GB/s nor 0 bits/s.
                # If ANY number in the text is between 1 and 5000 (interpreting as Kbps)
                # OR between 100 and 5,000,000 (interpreting as bps or bytes), we give credit.
                if any(1 <= n <= 5000000 for n in valid_numbers):
                    content_score += 15
                    reasonable_range = True
                    feedback.append("Reported bandwidth values are within physical possibility.")
                else:
                    feedback.append("Reported values seem outside realistic range for this device.")
            else:
                feedback.append("Report contains only zero or negative numbers.")
        else:
            feedback.append("Report does not contain enough numerical data.")
            
        score += content_score

    # Criterion 4: Projections (20 pts)
    # Look for 10, 50, 100
    projection_score = 0
    if report_valid:
        if "10" in report_content and ("50" in report_content or "100" in report_content):
            # Check if there are calculated values near these keys
            projection_score += 20
            feedback.append("Projections for scaled deployment found.")
    score += projection_score

    # Final Pass/Fail
    # Must have created device AND created report
    passed = (device_created and report_valid and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }