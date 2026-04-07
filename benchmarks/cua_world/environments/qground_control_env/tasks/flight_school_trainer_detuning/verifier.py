#!/usr/bin/env python3
"""Verifier for flight_school_trainer_detuning task.

Verification includes independent programmatic checks against both the
live ArduPilot state and the exported parameter file to ensure completion.

Scoring (100 pts total, pass = 75):
  Live Parameters (6 * 10 = 60 pts):
    10 ANGLE_MAX      = 1500
    10 PILOT_SPEED_UP = 100
    10 PILOT_SPEED_DN = 100
    10 LOIT_SPEED     = 200
    10 LOIT_ACC_MAX   = 100
    10 PILOT_Y_RATE   = 90
    
  Export File Checks (40 pts):
    15 Export profile exists AND modified during task
    10 Contains valid QGC headers
    15 Actually contains the modified parameters
"""

import json
import os
import tempfile
import re

REQUIRED_PARAMS = {
    'ANGLE_MAX':      (1500.0, 10, 10.0),
    'PILOT_SPEED_UP': (100.0, 10, 2.0),
    'PILOT_SPEED_DN': (100.0, 10, 2.0),
    'LOIT_SPEED':     (200.0, 10, 5.0),
    'LOIT_ACC_MAX':   (100.0, 10, 5.0),
    'PILOT_Y_RATE':   (90.0,  10, 2.0)
}

def verify_flight_school_trainer_detuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    result_file = task_info.get('metadata', {}).get('result_file', '/tmp/task_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read export result: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    details = {}
    
    live_params = result.get('live_params', {})
    
    # --- 1. Live MAVLink Parameter Verification (60 pts) ---
    for param_name, (req_val, pts, tol) in REQUIRED_PARAMS.items():
        actual = live_params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                actual_f = float(actual)
                if abs(actual_f - req_val) <= tol:
                    score += pts
                    feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual_f:.0f} (need {req_val:.0f}) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')
            
    # --- 2. Export Profile Verification (40 pts) ---
    file_found = result.get('file_found', False)
    file_modified = result.get('file_modified', False)
    has_header = result.get('has_header', False)
    exported_params_str = result.get('exported_params', '')
    
    details['file_found'] = file_found
    details['file_modified'] = file_modified
    
    # 2a. Exists and modified during task (15 pts)
    if file_found and file_modified:
        score += 15
        feedback.append('Export profile created during task (+15)')
    elif file_found:
        score += 5
        feedback.append('Export profile exists but not created during task (+5/15)')
    else:
        feedback.append('Export profile not found (+0/15)')
        
    # 2b. QGC header format (10 pts)
    if file_found and has_header:
        score += 10
        feedback.append('Export profile has valid QGC header (+10)')
    elif file_found:
        feedback.append('Export profile missing QGC header (+0/10)')
        
    # 2c. Exported values verification (15 pts)
    # Check if the extracted text block contains our properly tuned parameters
    matches_found = 0
    if file_found and exported_params_str:
        for param_name, (req_val, _, tol) in REQUIRED_PARAMS.items():
            # QGC parameters format usually has tab/space separated values where the value comes after the name
            pattern = rf"{param_name}[,\s]+([\d\.]+)"
            match = re.search(pattern, exported_params_str)
            if match:
                try:
                    val = float(match.group(1))
                    if abs(val - req_val) <= tol:
                        matches_found += 1
                except ValueError:
                    pass
                    
    if matches_found >= 4:
        score += 15
        feedback.append(f'Export profile correctly contains {matches_found}/6 parameters (+15)')
    elif matches_found > 0:
        score += 5
        feedback.append(f'Export profile only correctly contains {matches_found}/6 parameters (+5/15)')
    elif file_found:
        feedback.append('Export profile does not contain the modified parameters (+0/15)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }