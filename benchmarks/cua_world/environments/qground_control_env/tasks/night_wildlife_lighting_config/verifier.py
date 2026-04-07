#!/usr/bin/env python3
"""Verifier for night_wildlife_lighting_config task.

Checks hardware relay, RC mappings, and night flight dynamics parameters via pymavlink.
Includes anti-gaming logic to catch agents who fail to convert units (e.g., entering 3 instead of 300 cm/s).

Required parameters:
  RELAY_PIN   = 54    (AUX 5, default: 13)
  RC9_OPTION  = 28    (Relay1 On/Off, default: 0)
  WPNAV_SPEED = 300   (3 m/s -> 300 cm/s, default: 500)
  WPNAV_ACCEL = 100   (1 m/s/s -> 100 cm/s/s, default: 250)
  RTL_ALT     = 5000  (50 m -> 5000 cm, default: 1500)

Scoring (100 pts total, pass = 80):
  20 points per correctly set parameter.
"""

import json
import os
import tempfile

REQUIRED_PARAMS = {
    'RELAY_PIN':   (54.0,   20),
    'RC9_OPTION':  (28.0,   20),
    'WPNAV_SPEED': (300.0,  20),
    'WPNAV_ACCEL': (100.0,  20),
    'RTL_ALT':     (5000.0, 20),
}

# Define tight tolerances for integer/enum parameters, slight flexibility for nav values
TOLERANCES = {
    'RELAY_PIN':   0.4,
    'RC9_OPTION':  0.4,
    'WPNAV_SPEED': 5.0,
    'WPNAV_ACCEL': 5.0,
    'RTL_ALT':     10.0,
}

# Values that indicate the agent failed to convert units from the brief
UNIT_ERROR_CHECKS = {
    'WPNAV_SPEED': 3.0,   # Put 3 instead of 300
    'WPNAV_ACCEL': 1.0,   # Put 1 instead of 100
    'RTL_ALT':     50.0,  # Put 50 instead of 5000
}


def verify_night_wildlife_lighting_config(traj, env_info, task_info):
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

    if not result.get('connected', True) and all(result.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read.'
        }

    score = 0
    feedback = []
    details = {}

    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = result.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: not read (+0/{pts})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts})')
            continue

        tol = TOLERANCES.get(param_name, 1.0)
        
        # Check for common unit conversion errors first
        unit_err_val = UNIT_ERROR_CHECKS.get(param_name)
        if unit_err_val is not None and abs(actual_f - unit_err_val) <= tol:
            feedback.append(f'{param_name}={actual_f:.0f} (UNIT ERROR: you entered meters instead of centimeters) (+0/{pts})')
            continue

        if abs(actual_f - required_val) <= tol:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    passed = score >= 80
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }