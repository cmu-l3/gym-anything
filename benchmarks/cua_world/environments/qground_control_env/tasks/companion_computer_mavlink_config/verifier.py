#!/usr/bin/env python3
"""Verifier for companion_computer_mavlink_config task.

Checks 9 stream rate and serial configuration parameters via pymavlink.

Required values:
  SERIAL2_PROTOCOL = 2
  SERIAL2_BAUD     = 921
  SR2_POSITION     = 50
  SR2_EXTRA1       = 50
  SR2_EXTRA2       = 20
  SR2_EXTRA3       = 10
  SR2_RC_CHAN      = 20
  SR2_EXT_STAT     = 5
  SR2_RAW_SENS     = 10

Scoring (100 pts total, pass = 75):
  SERIAL2_PROTOCOL : 12 pts
  SERIAL2_BAUD     : 12 pts
  SR2_POSITION     : 11 pts
  SR2_EXTRA1       : 11 pts
  SR2_EXTRA2       : 11 pts
  SR2_EXTRA3       : 11 pts
  SR2_RC_CHAN      : 11 pts
  SR2_EXT_STAT     : 11 pts
  SR2_RAW_SENS     : 10 pts
"""

import json
import os
import tempfile

SCORING_MAP = {
    'SERIAL2_PROTOCOL': (2.0, 12),
    'SERIAL2_BAUD': (921.0, 12),
    'SR2_POSITION': (50.0, 11),
    'SR2_EXTRA1': (50.0, 11),
    'SR2_EXTRA2': (20.0, 11),
    'SR2_EXTRA3': (10.0, 11),
    'SR2_RC_CHAN': (20.0, 11),
    'SR2_EXT_STAT': (5.0, 11),
    'SR2_RAW_SENS': (10.0, 10),
}


def verify_companion_mavlink_config(traj, env_info, task_info):
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
    if not params.get('connected', True) and all(params.get(p) is None for p in SCORING_MAP):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read.'
        }

    score = 0
    feedback = []
    details = {}

    for param_name, (required_val, pts) in SCORING_MAP.items():
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

        # We allow a very tight tolerance (0.5) because these are integer-based parameters
        if abs(actual_f - required_val) < 0.5:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }