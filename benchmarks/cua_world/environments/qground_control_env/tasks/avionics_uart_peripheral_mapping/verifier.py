#!/usr/bin/env python3
"""Verifier for avionics_uart_peripheral_mapping task.

Queries the 8 serial parameters required by the wiring schematic and
scores the agent based on correct configuration.

Required Values:
  SERIAL3_PROTOCOL = 2
  SERIAL3_BAUD = 921
  SERIAL4_PROTOCOL = 32
  SERIAL4_BAUD = 115
  SERIAL5_PROTOCOL = 16
  SERIAL5_BAUD = 115
  SERIAL6_PROTOCOL = 9
  SERIAL6_BAUD = 19

Scoring (100 pts total, pass = 75):
  Each protocol parameter: 12 pts
  Each baud rate parameter: 13 pts
  (12+13)*4 = 100 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_PARAMS = {
    'SERIAL3_PROTOCOL': (2.0, 12),
    'SERIAL3_BAUD':     (921.0, 13),
    'SERIAL4_PROTOCOL': (32.0, 12),
    'SERIAL4_BAUD':     (115.0, 13),
    'SERIAL5_PROTOCOL': (16.0, 12),
    'SERIAL5_BAUD':     (115.0, 13),
    'SERIAL6_PROTOCOL': (9.0, 12),
    'SERIAL6_BAUD':     (19.0, 13),
}

TOLERANCE = 0.5  # Precision tolerance for float-represented MAVLink integers

def verify_uart_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read export result: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get('connected', True) and all(result.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read. The vehicle may have crashed or locked up.'
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

        if abs(actual_f - required_val) <= TOLERANCE:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    # Pass threshold is 75 (requires 6 of 8 parameters to be perfect)
    passed = score >= 75

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }