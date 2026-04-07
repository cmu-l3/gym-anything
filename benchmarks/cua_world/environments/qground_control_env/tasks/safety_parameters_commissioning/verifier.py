#!/usr/bin/env python3
"""Verifier for safety_parameters_commissioning task.

Checks all 6 safety parameters via pymavlink values recorded in export_result.sh.

Required values (all different from factory defaults):
  FS_BATT_ENABLE  = 2     (default: 0)
  RTL_ALT         = 2500  (default: 1500)
  FENCE_ENABLE    = 1     (default: 0)
  FENCE_ALT_MAX   = 8000  (default: 10000)
  FS_GCS_ENABLE   = 1     (default: 0)
  LAND_SPEED_HIGH = 150   (default: 0)

Scoring (100 pts total, pass = 60):
  Each parameter: 16 pts  (6 × 16 = 96, rounded: first 4 = 17, last 2 = 16)
  Actually: 17+17+17+17+16+16 = 100
"""

import json
import os
import tempfile


REQUIRED_PARAMS = {
    'FS_BATT_ENABLE':  (2.0,   17),
    'RTL_ALT':         (2500.0, 17),
    'FENCE_ENABLE':    (1.0,   17),
    'FENCE_ALT_MAX':   (8000.0, 17),
    'FS_GCS_ENABLE':   (1.0,   16),
    'LAND_SPEED_HIGH': (150.0, 16),
}
# Tolerances per parameter — tight for small integers, loose for large values
TOLERANCES = {
    'FS_BATT_ENABLE':  0.4,
    'RTL_ALT':         10.0,
    'FENCE_ENABLE':    0.4,
    'FENCE_ALT_MAX':   10.0,
    'FS_GCS_ENABLE':   0.4,
    'LAND_SPEED_HIGH': 5.0,
}


def verify_safety_parameters_commissioning(traj, env_info, task_info):
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
            'feedback': 'SITL not reachable during export — no parameters could be read'
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
        if abs(actual_f - required_val) <= tol:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    passed = score >= 60
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }
