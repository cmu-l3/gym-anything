#!/usr/bin/env python3
"""Verifier for adsb_traffic_avoidance_config task.

Checks live ADSB/Avoidance parameters on the flight controller and verifies
that a parameter backup was exported via QGC.

Required live parameters:
  ADSB_ENABLE   = 1
  AVD_ENABLE    = 1
  AVD_W_DIST_XY = 1500
  AVD_W_DIST_Z  = 300
  AVD_F_DIST_XY = 500
  AVD_F_DIST_Z  = 150
  AVD_F_ACTION  = 2

Scoring (100 pts total, pass = 70):
  Each of the 7 parameters is worth 10 points (70 points total).
  Export file exists & was created/modified during task (20 points).
  Export file contains parameter data like AVD_ENABLE (10 points).
"""

import json
import os
import tempfile

REQUIRED_PARAMS = {
    'ADSB_ENABLE':   (1.0, 10),
    'AVD_ENABLE':    (1.0, 10),
    'AVD_W_DIST_XY': (1500.0, 10),
    'AVD_W_DIST_Z':  (300.0, 10),
    'AVD_F_DIST_XY': (500.0, 10),
    'AVD_F_DIST_Z':  (150.0, 10),
    'AVD_F_ACTION':  (2.0, 10),
}

TOLERANCES = {
    'ADSB_ENABLE':   0.4,
    'AVD_ENABLE':    0.4,
    'AVD_W_DIST_XY': 5.0,
    'AVD_W_DIST_Z':  5.0,
    'AVD_F_DIST_XY': 5.0,
    'AVD_F_DIST_Z':  5.0,
    'AVD_F_ACTION':  0.4,
}

def verify_adsb_traffic_avoidance_config(traj, env_info, task_info):
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

    live_params = result.get('live_params', {})
    if not live_params.get('connected', True) and all(live_params.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be verified'
        }

    score = 0
    feedback = []
    details = {}

    # --- Live Parameter Checks (70 points total) ---
    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = live_params.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: not found (+0/{pts})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts})')
            continue

        tol = TOLERANCES.get(param_name, 1.0)
        if abs(actual_f - required_val) <= tol:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    # --- Parameter File Backup Checks (30 points total) ---
    file_found = result.get('file_found', False)
    file_modified = result.get('file_modified', False)
    file_contains_avd = result.get('file_contains_avd', False)
    
    details['file_found'] = file_found
    details['file_modified'] = file_modified
    details['file_contains_avd'] = file_contains_avd

    if file_found and file_modified:
        score += 20
        feedback.append('Backup file saved during task (+20)')
    elif file_found:
        score += 5
        feedback.append('Backup file found but not modified during task (+5)')
    else:
        feedback.append('Backup file not found at expected path (+0/20)')

    if file_found and file_contains_avd:
        score += 10
        feedback.append('Backup file contains expected param data (+10)')
    elif file_found:
        feedback.append('Backup file missing expected AVD parameters (+0/10)')

    # Overall pass criteria: 70 points
    passed = score >= 70
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }