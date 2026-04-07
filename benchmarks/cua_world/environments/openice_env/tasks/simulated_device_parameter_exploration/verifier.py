#!/usr/bin/env python3
"""
Verifier for simulated_device_parameter_exploration task in OpenICE.

Scoring Breakdown (100 points total):
1. Device Creation (35 pts):
   - Evidence of creating distinct device types (Multiparameter, Capno, PulseOx, etc.)
   - 8 pts each for first 3 types, +6 for 4th, +5 for 5th.
2. UI Exploration (10 pts):
   - Significant window count increase (>3) implies detail views opened.
3. Catalog File Mechanics (10 pts):
   - File exists, valid size (>500 bytes), valid timestamp.
4. Catalog Content Quality (45 pts):
   - Mentions correct device types (regex match).
   - Mentions real physiological parameters (Heart Rate, SpO2, etc.).
   - Classifies data as "Numeric" vs "Waveform".
   - Includes Summary section.

Pass Threshold: 60 points.
Gate Condition: If < 2 devices created AND no report file -> 0 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_simulated_device_exploration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Read result JSON
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    devices_detected = result.get('distinct_devices_detected', 0)
    window_increase = result.get('window_increase', 0)
    report = result.get('report', {})
    
    device_details = result.get('device_details', {})
    
    # GATE CHECK: Anti-gaming
    # If agent did almost nothing (no devices, no report, no windows opened)
    if devices_detected < 2 and not report.get('exists') and window_increase < 2:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "GATE FAILURE: No meaningful activity detected. No devices created and no report generated."
        }

    # --- 1. Device Creation (Max 35 pts) ---
    # Multiparameter (8), Capno (8), PulseOx (8), Infusion/NIBP/Other (6 + 5)
    dev_score = 0
    dev_types_found = []
    
    if device_details.get('multiparameter'):
        dev_score += 8
        dev_types_found.append("Multiparameter")
    
    if device_details.get('capnograph'):
        dev_score += 8
        dev_types_found.append("Capnograph")
        
    if device_details.get('pulseox'):
        dev_score += 8
        dev_types_found.append("PulseOx")
        
    # Bonus points for other devices
    extras = 0
    if device_details.get('infusion'): extras += 1
    if device_details.get('nibp'): extras += 1
    
    if extras > 0:
        dev_score += 6
        dev_types_found.append("Infusion/NIBP")
    if extras > 1:
        dev_score += 5
    
    score += dev_score
    feedback.append(f"Devices created ({dev_score}/35 pts): {', '.join(dev_types_found)}")

    # --- 2. UI Exploration (Max 10 pts) ---
    # Opening a detail view creates a new window.
    # We expect at least 3 detail views + possibly device creation dialogs.
    # Window increase >= 3 is good evidence.
    ui_score = 0
    if window_increase >= 5:
        ui_score = 10
    elif window_increase >= 3:
        ui_score = 7
    elif window_increase >= 1:
        ui_score = 3
    
    score += ui_score
    feedback.append(f"UI Exploration ({ui_score}/10 pts): Window count increased by {window_increase}")

    # --- 3. Catalog File Mechanics (Max 10 pts) ---
    mech_score = 0
    if report.get('exists'):
        if report.get('valid_timestamp'):
            mech_score += 5
        else:
            feedback.append("Report file timestamp invalid (modified before task start?)")
            
        if report.get('size', 0) >= 500:
            mech_score += 5
        elif report.get('size', 0) >= 100:
            mech_score += 3
        else:
            feedback.append("Report file too small (<100 bytes)")
            
    score += mech_score
    feedback.append(f"File Mechanics ({mech_score}/10 pts): Exists & Valid")

    # --- 4. Catalog Content Quality (Max 45 pts) ---
    content_score = 0
    if report.get('exists'):
        # Mentioning device types in report (we can infer this if regex count matched devices)
        # Using the distinct devices count from logs as a proxy for what SHOULD be in report,
        # but here we rely on the grep analysis from export_result.sh if possible.
        # Since we didn't grep specifically for device names in export_result.sh (only logs),
        # we'll use structure_score as proxy for "device sections".
        
        # Structure (headers)
        if report.get('structure_score', 0) >= 3:
            content_score += 5
        
        # Parameter count (mentions "Heart Rate", "SpO2", etc.)
        param_count = report.get('distinct_params_found', 0)
        if param_count >= 5:
            content_score += 15
        elif param_count >= 3:
            content_score += 8
        elif param_count >= 1:
            content_score += 3
            
        # Classification (Numeric vs Waveform)
        if report.get('has_classification'):
            content_score += 15
            
        # Summary section
        if report.get('has_summary'):
            content_score += 10
            
    score += content_score
    feedback.append(f"Report Content ({content_score}/45 pts): Params found={report.get('distinct_params_found', 0)}, Structure ok={report.get('structure_score', 0)>=3}")

    # --- Final Result ---
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "devices_detected": devices_detected,
            "window_increase": window_increase,
            "report_stats": report
        }
    }