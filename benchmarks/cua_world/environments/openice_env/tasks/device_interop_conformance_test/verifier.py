#!/usr/bin/env python3
"""Verification script for device_interop_conformance_test"""

import json
import tempfile
import os
import sys

def verify_conformance_test(traj, env_info, task_info):
    """
    Verify the IHE Conformance Test task.
    
    Scores based on:
    1. Device Creation (logs/windows)
    2. Clinical App Launch
    3. Evidence Screenshots (existence + timestamp)
    4. Report Quality (sections + technical terms)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    task_start = int(result.get("task_start_time", 0))

    # --- Device 1: Multiparameter Monitor (15 pts) ---
    dev = result.get("devices", {})
    monitor_detected = dev.get("monitor_in_log", False) or dev.get("monitor_in_window", False)
    if monitor_detected:
        score += 15
        feedback_parts.append("Multiparameter Monitor detected")
    else:
        feedback_parts.append("Multiparameter Monitor MISSING")

    # --- Device 2: NIBP (15 pts) ---
    nibp_detected = dev.get("nibp_in_log", False) or dev.get("nibp_in_window", False)
    if nibp_detected:
        score += 15
        feedback_parts.append("NIBP device detected")
    else:
        feedback_parts.append("NIBP device MISSING")

    # --- Vital Signs App (15 pts) ---
    app = result.get("clinical_app", {})
    vitals_detected = app.get("vitals_in_log", False) or app.get("vitals_in_window", False)
    if vitals_detected:
        score += 15
        feedback_parts.append("Vital Signs app detected")
    else:
        feedback_parts.append("Vital Signs app MISSING")

    # --- Screenshot 1: Vitals (5 pts) ---
    ss = result.get("screenshots", {})
    ss_vitals = ss.get("vitals", {})
    if (ss_vitals.get("exists", False) and
        ss_vitals.get("size", 0) > 10240 and
        int(ss_vitals.get("mtime", 0)) > task_start):
        score += 5
        feedback_parts.append("Vitals screenshot OK")
    else:
        feedback_parts.append("Vitals screenshot missing/invalid")

    # --- Screenshot 2: Devices (5 pts) ---
    ss_devices = ss.get("devices", {})
    if (ss_devices.get("exists", False) and
        ss_devices.get("size", 0) > 10240 and
        int(ss_devices.get("mtime", 0)) > task_start):
        score += 5
        feedback_parts.append("Devices screenshot OK")
    else:
        feedback_parts.append("Devices screenshot missing/invalid")

    # --- Report: Exists with substance (10 pts) ---
    rpt = result.get("report", {})
    report_valid = (rpt.get("exists", False) and
                    rpt.get("size", 0) >= 300 and
                    int(rpt.get("mtime", 0)) > task_start)
    if report_valid:
        score += 10
        feedback_parts.append("Report file OK")
    else:
        feedback_parts.append("Report file missing/empty")

    # --- Report: Required sections (15 pts, 3 per section) ---
    sections = rpt.get("sections", {})
    section_count = int(sections.get("count", 0))
    section_points = min(section_count * 3, 15)
    score += section_points
    if section_count < 5:
        feedback_parts.append(f"Report missing sections ({section_count}/5)")

    # --- Report Content Quality (20 pts total) ---
    quality = rpt.get("content_quality", {})
    
    # Mentions both device types (8 pts)
    if quality.get("has_both_devices", False):
        score += 8
    
    # IHE terminology (6 pts)
    ihe_points = 0
    if quality.get("has_ihe_roles", False):
        ihe_points += 3
    if quality.get("has_dds_reference", False):
        ihe_points += 3
    score += ihe_points
    
    # Verdict (6 pts)
    if quality.get("has_verdict", False):
        score += 6

    # --- GATE CONDITION ---
    # If agent did effectively nothing (no devices, no report, no windows), force 0
    devices_detected = int(monitor_detected) + int(nibp_detected)
    windows = result.get("windows", {})
    window_increase = int(windows.get("increase", 0))
    
    if devices_detected < 1 and not rpt.get("exists", False) and window_increase < 2:
        score = 0
        feedback_parts = ["GATE FAILURE: No devices created and no report found"]

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }