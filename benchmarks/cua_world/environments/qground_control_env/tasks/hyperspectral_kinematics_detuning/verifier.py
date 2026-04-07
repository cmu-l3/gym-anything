#!/usr/bin/env python3
"""Verifier for hyperspectral_kinematics_detuning task.

Checks all 6 kinematics parameters via pymavlink values recorded in export_result.sh.
Checks for the presence and content of the sign-off file.

Required values (converted from m/s and degrees to cm/s and centidegrees):
  ANGLE_MAX      = 1500 (15 degrees)
  WPNAV_SPEED    = 300  (3.0 m/s)
  WPNAV_ACCEL    = 100  (1.0 m/s/s)
  WPNAV_ACCEL_Z  = 50   (0.5 m/s/s)
  WPNAV_SPEED_UP = 150  (1.5 m/s)
  WPNAV_SPEED_DN = 100  (1.0 m/s)

Scoring (100 pts total, pass = 75):
  15  ANGLE_MAX
  15  WPNAV_SPEED
  15  WPNAV_ACCEL
  15  WPNAV_ACCEL_Z
  10  WPNAV_SPEED_UP
  10  WPNAV_SPEED_DN
  10  Signoff file exists and created during task
  10  Signoff file > 50 bytes and contains required keywords
"""

import json
import os
import tempfile


REQUIRED_PARAMS = {
    'ANGLE_MAX':      (1500.0, 15),
    'WPNAV_SPEED':    (300.0,  15),
    'WPNAV_ACCEL':    (100.0,  15),
    'WPNAV_ACCEL_Z':  (50.0,   15),
    'WPNAV_SPEED_UP': (150.0,  10),
    'WPNAV_SPEED_DN': (100.0,  10),
}

# Tolerances allow for slight float rounding when saving
TOLERANCES = {
    'ANGLE_MAX':      5.0,
    'WPNAV_SPEED':    2.0,
    'WPNAV_ACCEL':    2.0,
    'WPNAV_ACCEL_Z':  2.0,
    'WPNAV_SPEED_UP': 2.0,
    'WPNAV_SPEED_DN': 2.0,
}

def verify_hyperspectral_kinematics_detuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

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

    if not result.get('connected', True) and all(result.get('params', {}).get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read'
        }

    score = 0
    feedback = []
    details = {}
    params = result.get('params', {})

    # --- 1. Parameter Checks ---
    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: not read (+0/{pts})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts})')
            continue

        tol = TOLERANCES.get(param_name, 2.0)
        if abs(actual_f - required_val) <= tol:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    # --- 2. Signoff File Checks ---
    signoff_found = result.get('signoff_found', False)
    signoff_modified = result.get('signoff_modified', False)
    signoff_size = result.get('signoff_size', 0)
    
    details['signoff_found'] = signoff_found
    details['signoff_modified'] = signoff_modified
    details['signoff_size'] = signoff_size

    if signoff_found and signoff_modified:
        score += 10
        feedback.append('Signoff file created during task (+10)')
    elif signoff_found:
        score += 5
        feedback.append('Signoff file exists but not created during task (+5/10)')
    else:
        feedback.append('Signoff file not found (+0/10)')

    # Content checks (10 pts)
    if signoff_found:
        content = result.get('signoff_content', '')
        if isinstance(content, str):
            content = content.replace('\\n', '\n').replace('\\t', '\t').lower()
        
        has_size = signoff_size >= 50
        has_keywords = 'hyperspectral' in content or 'pika' in content
        
        if has_size and has_keywords:
            score += 10
            feedback.append('Signoff file is valid (>50 bytes and mentions payload) (+10)')
        elif has_size:
            score += 5
            feedback.append('Signoff file is long enough but missing keywords (+5/10)')
        elif has_keywords:
            score += 5
            feedback.append(f'Signoff file mentions payload but is too short ({signoff_size} bytes) (+5/10)')
        else:
            feedback.append('Signoff file is too short and missing keywords (+0/10)')
    else:
        feedback.append('Signoff file content check skipped (+0/10)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }