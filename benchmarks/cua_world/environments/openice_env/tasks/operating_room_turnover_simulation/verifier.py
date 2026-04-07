#!/usr/bin/env python3
"""Verifier for operating_room_turnover_simulation task.

Verification Logic:
1. Parse the window history log to reconstruct the timeline of open windows.
2. Verify State 1 (Case A): Timeframe where "Capnograph" AND "Multiparameter" windows existed.
3. Verify State 2 (Turnover): Timeframe AFTER State 1 where NO device windows existed (but Supervisor remained).
4. Verify State 3 (Case B): Timeframe AFTER State 2 where "Infusion Pump" AND "Pulse Oximeter" windows existed.
5. Verify Documentation: Check log file content.

Device Window Keywords:
- Capnograph: "Capnograph", "CO2"
- Multiparameter: "Multiparameter", "Monitor"
- Infusion Pump: "Infusion", "Pump"
- Pulse Oximeter: "Pulse", "Oximeter", "SpO2"
"""

import json
import tempfile
import os
import re

def parse_window_history(history_text):
    """
    Parses the raw window history log into a list of timeframes.
    Returns: List of sets, where each set contains lowercased titles of windows open at that time.
    """
    timeframes = []
    current_windows = set()
    
    # Split by the timeframe header
    chunks = re.split(r'--- TIMEFRAME \d+ ---', history_text)
    
    for chunk in chunks:
        if not chunk.strip():
            continue
            
        # Parse lines in this chunk
        titles = set()
        for line in chunk.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 4:
                # wmctrl output: ID workspace hostname TITLE...
                title = " ".join(parts[4:]).lower()
                titles.add(title)
        
        timeframes.append(titles)
        
    return timeframes

def identify_devices(window_titles):
    """Identify which devices are present in a set of window titles."""
    devices = set()
    for title in window_titles:
        if "capnograph" in title or "co2" in title:
            devices.add("capnograph")
        if "multiparameter" in title or "monitor" in title:
            devices.add("multiparameter")
        if "infusion" in title or "pump" in title:
            devices.add("infusion_pump")
        if "pulse" in title or "oximeter" in title or "spo2" in title:
            devices.add("pulse_oximeter")
    return devices

def verify_operating_room_turnover(traj, env_info, task_info):
    # Get copy function
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

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # Check 1: OpenICE Running (Critical)
    if not result.get('openice_running', False):
        return {"passed": False, "score": 0, "feedback": "FAIL: OpenICE application was closed or crashed."}

    # Parse History
    history_log = result.get('window_history_log', "")
    timeframes = parse_window_history(history_log)
    
    if not timeframes:
        return {"passed": False, "score": 0, "feedback": "FAIL: No window history data collected."}

    # Timeline Analysis
    case_a_detected = False
    clean_state_detected = False
    case_b_detected = False
    
    # State tracking
    case_a_index = -1
    clean_index = -1
    
    # Step 1: Find Case A (Capnograph + Multiparameter)
    for i, windows in enumerate(timeframes):
        devices = identify_devices(windows)
        if "capnograph" in devices and "multiparameter" in devices:
            case_a_detected = True
            case_a_index = i
            break
            
    # Step 2: Find Clean State (No devices) AFTER Case A
    if case_a_detected:
        for i in range(case_a_index + 1, len(timeframes)):
            devices = identify_devices(timeframes[i])
            # Check if any device adapter is present
            if len(devices) == 0:
                clean_state_detected = True
                clean_index = i
                break
                
    # Step 3: Find Case B (Infusion + Pulse Ox) AFTER Clean State
    if clean_state_detected:
        for i in range(clean_index + 1, len(timeframes)):
            devices = identify_devices(timeframes[i])
            if "infusion_pump" in devices and "pulse_oximeter" in devices:
                case_b_detected = True
                break

    # Scoring Logic
    
    # Case A Setup (25 pts)
    if case_a_detected:
        score += 25
        feedback_parts.append("Case A setup verified")
    else:
        feedback_parts.append("Case A setup missing (Capnograph + Multiparameter not seen together)")

    # Clean Turnover (30 pts)
    if case_a_detected and clean_state_detected:
        score += 30
        feedback_parts.append("Clean turnover verified (all devices closed)")
    elif case_a_detected and not clean_state_detected:
        feedback_parts.append("Failed to clean up Case A devices before starting Case B")
    
    # Case B Setup (25 pts)
    if clean_state_detected and case_b_detected:
        score += 25
        feedback_parts.append("Case B setup verified")
    elif not clean_state_detected and case_b_detected:
        # If they skipped cleanup but still set up B, give partial points? 
        # No, strict protocol requires cleanup.
        feedback_parts.append("Case B setup detected but turnover protocol violated (cleanup skipped)")
        
    # Turnover Log (20 pts)
    log_exists = result.get('log_file_exists', False)
    log_content = result.get('log_file_content', "").lower()
    
    if log_exists:
        if "turnover complete" in log_content:
            score += 10
            feedback_parts.append("Log file confirms turnover")
        else:
            score += 5
            feedback_parts.append("Log file exists but missing 'Turnover Complete'")
            
        if "infusion" in log_content or "pump" in log_content:
            score += 5
        if "pulse" in log_content or "oximeter" in log_content:
            score += 5
    else:
        feedback_parts.append("Turnover log file not found")

    # Pass Threshold
    # Must do Setup A, Cleanup, and Setup B (25+30+25 = 80) to pass comfortably
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "case_a_detected": case_a_detected,
            "clean_state_detected": clean_state_detected,
            "case_b_detected": case_b_detected,
            "timeframes_count": len(timeframes)
        }
    }