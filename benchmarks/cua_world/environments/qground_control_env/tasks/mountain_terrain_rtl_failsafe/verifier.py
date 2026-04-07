#!/usr/bin/env python3
"""Verifier for mountain_terrain_rtl_failsafe task.

Checks 6 ArduPilot parameters via pymavlink values recorded in export_result.sh.

Required values:
  TERRAIN_ENABLE = 1
  RTL_ALT = 20000
  RTL_CLIMB_MIN = 5000
  RTL_SPEED = 800
  RTL_ALT_FINAL = 1000
  FS_GCS_ENABLE = 1

Scoring (100 pts total, pass = 66):
  TERRAIN_ENABLE : 16 pts
  RTL_ALT        : 17 pts
  RTL_CLIMB_MIN  : 17 pts
  RTL_SPEED      : 17 pts
  RTL_ALT_FINAL  : 17 pts
  FS_GCS_ENABLE  : 16 pts

(Total = 16 + 17 + 17 + 17 + 17 + 16 = 100)
"""

import json
import os
import tempfile


REQUIRED_PARAMS = {
    'TERRAIN_ENABLE': (1.0, 16),
    'RTL_ALT': (20000.0, 17),
    'RTL_CLIMB_MIN': (5000.0, 17),
    'RTL_SPEED': (800.0, 17),
    'RTL_ALT_FINAL': (1000.0, 17),
    'FS_GCS_ENABLE': (1.0, 16),
}

# Tolerances
TOLERANCES = {
    'TERRAIN_ENABLE': 0.4,
    'RTL_ALT': 10.0,
    'RTL_CLIMB_MIN': 10.0,
    'RTL_SPEED': 10.0,
    'RTL_ALT_FINAL': 10.0,
    'FS_GCS_ENABLE': 0.4,
}

def verify_mountain_terrain_rtl_failsafe(traj, env_info, task_info):
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

    params = result.get('params', {})
    
    if not params.get('connected', True) and all(params.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read',
            'details': {'connected': False}
        }

    score = 0
    feedback = []
    details = {}

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

        tol = TOLERANCES.get(param_name, 1.0)
        if abs(actual_f - required_val) <= tol:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    passed = score >= 66
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }