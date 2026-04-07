#!/usr/bin/env python3
"""Verifier for ag_sprayer_system_config task.

Checks 6 spray system parameters via pymavlink values recorded in export_result.sh.

Required values (all different from factory defaults):
  SPRAY_ENABLE     = 1    (default: 0)
  SERVO9_FUNCTION  = 22   (default: 0)
  SERVO10_FUNCTION = 23   (default: 0)
  SPRAY_SPEED_MIN  = 250  (default: 100)
  SPRAY_PUMP_MIN   = 15   (default: 0)
  SPRAY_PUMP_RATE  = 80   (default: 10)

Scoring (100 pts total, pass = 68):
  SPRAY_ENABLE     (18 pts)
  SERVO9_FUNCTION  (18 pts)
  SERVO10_FUNCTION (16 pts)
  SPRAY_SPEED_MIN  (16 pts)
  SPRAY_PUMP_MIN   (16 pts)
  SPRAY_PUMP_RATE  (16 pts)
"""

import json
import os
import tempfile

REQUIRED_PARAMS = {
    'SPRAY_ENABLE':     (1.0,   18),
    'SERVO9_FUNCTION':  (22.0,  18),
    'SERVO10_FUNCTION': (23.0,  16),
    'SPRAY_SPEED_MIN':  (250.0, 16),
    'SPRAY_PUMP_MIN':   (15.0,  16),
    'SPRAY_PUMP_RATE':  (80.0,  16),
}

# Tolerances allow minor floating point rounding discrepancies from QGC
TOLERANCES = {
    'SPRAY_ENABLE':     0.4,
    'SERVO9_FUNCTION':  0.4,
    'SERVO10_FUNCTION': 0.4,
    'SPRAY_SPEED_MIN':  1.0,
    'SPRAY_PUMP_MIN':   1.0,
    'SPRAY_PUMP_RATE':  1.0,
}

def verify_ag_sprayer_system_config(traj, env_info, task_info):
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
            'feedback': 'SITL not reachable during export — no parameters could be read'
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

    # Threshold requires enabling the system AND correctly mapping most settings
    passed = score >= 68
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }