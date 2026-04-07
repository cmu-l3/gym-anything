#!/usr/bin/env python3
"""
Verifier for mews_device_feasibility task.
Evaluates device configuration, screenshot evidence, and clinical feasibility report.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mews_feasibility(traj, env_info, task_info):
    """
    Verifies the MEWS device feasibility task.
    
    Scoring Breakdown (100 pts total):
    - [30 pts] Device Configuration (10 pts each for Multiparameter, PulseOx, Temp/3rd device)
    - [15 pts] Clinical App Launch (Vital Signs)
    - [10 pts] Screenshot created and valid
    - [ 5 pts] Report file created
    - [40 pts] Report Content Quality:
        - [10] Inventory lists devices
        - [10] MEWS table present
        - [15] Gap Analysis mentions AVPU/Consciousness/Manual requirement (CRITICAL)
        - [ 5] Recommendation present
    
    Gate: Score is 0 if < 1 device created AND no report found.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Report Text Content (if it exists)
    report_content = ""
    report_path = result.get('report', {}).get('path', '')
    report_exists = result.get('report', {}).get('exists', False)
    
    if report_exists and report_path:
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_txt.name)
            with open(temp_txt.name, 'r', errors='ignore') as f:
                report_content = f.read().lower() # Convert to lower for case-insensitive matching
        except Exception as e:
            logger.warning(f"Could not read report content: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)

    # --- Scoring Logic ---
    score = 0
    feedback = []
    
    # Logs and Window data
    logs = result.get('logs', {})
    wins = result.get('windows', {})
    
    # 1. Device Configuration (30 pts)
    # Detect Multiparameter
    has_multi = logs.get('multiparam_matches', 0) > 0 or wins.get('multiparam_visible', 0) > 0
    # Detect Pulse Ox
    has_pulse = logs.get('pulseox_matches', 0) > 0 or wins.get('pulseox_visible', 0) > 0
    # Detect Temp (or a 3rd distinct device)
    has_temp = logs.get('temp_matches', 0) > 0 or wins.get('temp_visible', 0) > 0
    # Fallback: Check total new windows if specific types hard to detect
    total_new_wins = wins.get('new_count', 0)
    
    devices_found = 0
    if has_multi: devices_found += 1
    if has_pulse: devices_found += 1
    if has_temp: devices_found += 1
    
    # Fallback logic: if specific types not found but 3 windows created, give partial credit
    if devices_found < 3 and total_new_wins >= 3:
        devices_found = max(devices_found, 3) # Assume valid if 3+ windows created
    elif devices_found < 2 and total_new_wins >= 2:
        devices_found = max(devices_found, 2)

    score += (devices_found * 10)
    feedback.append(f"Devices detected: {devices_found}/3 ({devices_found*10} pts)")

    # 2. App Launch (15 pts)
    app_launched = logs.get('app_launch_matches', 0) > 0 or wins.get('vitals_app_visible', 0) > 0
    if app_launched:
        score += 15
        feedback.append("Vital Signs app launched (15 pts)")
    else:
        feedback.append("Vital Signs app not detected")

    # 3. Screenshot (10 pts)
    ss_info = result.get('screenshot', {})
    if ss_info.get('exists') and ss_info.get('size_bytes', 0) > 5000:
        score += 10
        feedback.append("Screenshot valid (10 pts)")
    else:
        feedback.append("Screenshot missing or empty")

    # 4. Report Existence (5 pts)
    if report_exists and len(report_content) > 100:
        score += 5
        feedback.append("Report file exists (5 pts)")
    else:
        feedback.append("Report missing or too short")

    # 5. Report Content Analysis (40 pts)
    if report_content:
        # A. Inventory (10 pts)
        # Check for mention of device types
        if 'monitor' in report_content and ('oximeter' in report_content or 'spo2' in report_content):
            score += 10
            feedback.append("Report: Device inventory present (10 pts)")
        else:
            feedback.append("Report: Device inventory incomplete")

        # B. MEWS Table (10 pts)
        # Check for scoring related terms
        if 'score' in report_content and ('range' in report_content or any(c.isdigit() for c in report_content)):
            score += 10
            feedback.append("Report: MEWS table/ranges present (10 pts)")
        else:
            feedback.append("Report: MEWS scoring ranges missing")

        # C. Automation Gap Analysis (15 pts) - CRITICAL
        # Must mention Consciousness, AVPU, or Alert/Voice/Pain/Unresponsive AND manual/nurse
        has_consciousness = any(term in report_content for term in ['avpu', 'conscious', 'coma', 'alert', 'voice', 'pain'])
        has_limitation = any(term in report_content for term in ['manual', 'nurse', 'human', 'assess', 'cannot', 'not auto', 'gap'])
        
        if has_consciousness and has_limitation:
            score += 15
            feedback.append("Report: Gap Analysis correctly identifies AVPU/Consciousness (15 pts)")
        elif has_consciousness:
            score += 7
            feedback.append("Report: Mentions consciousness but misses manual entry requirement (7 pts)")
        else:
            feedback.append("Report: Failed to identify consciousness/AVPU gap")

        # D. Recommendation (5 pts)
        if any(term in report_content for term in ['recommend', 'conclusion', 'summary', 'feasible', 'suitable']):
            score += 5
            feedback.append("Report: Recommendation present (5 pts)")
    else:
        feedback.append("Report content analysis skipped (no file)")

    # Gate Condition
    if devices_found < 1 and not report_exists:
        score = 0
        feedback = ["GATE FAILURE: No devices created and no report written. No meaningful work detected."]

    passed = score >= 60 and result.get('app_running', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }