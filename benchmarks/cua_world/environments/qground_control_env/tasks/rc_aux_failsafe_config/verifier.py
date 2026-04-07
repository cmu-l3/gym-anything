#!/usr/bin/env python3
"""Verifier for rc_aux_failsafe_config task.

Checks all 7 RC and failsafe parameters via pymavlink values recorded in export_result.sh.

Required values (all different from factory defaults):
  RC7_OPTION     = 41   (default: 0)
  RC8_OPTION     = 31   (default: 0)
  RC9_OPTION     = 15   (default: 0)
  RC10_OPTION    = 11   (default: 0)
  FS_THR_ENABLE  = 2    (default: 0)
  FS_THR_VALUE   = 925  (default: 975)
  PILOT_THR_FILT = 4    (default: 0)

Scoring (100 pts total, pass = 70):
  15 pts each for RC7_OPTION, RC8_OPTION, RC9_OPTION, RC10_OPTION, FS_THR_ENABLE
  13 pts for FS_THR_VALUE
  12 pts for PILOT_THR_FILT
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_PARAMS = {
    'RC7_OPTION':     (41.0,  15),
    'RC8_OPTION':     (31.0,  15),
    'RC9_OPTION':     (15.0,  15),
    'RC10_OPTION':    (11.0,  15),
    'FS_THR_ENABLE':  (2.0,   15),
    'FS_THR_VALUE':   (925.0, 13),
    'PILOT_THR_FILT': (4.0,   12),
}

TOLERANCES = {
    'RC7_OPTION':     0.5,
    'RC8_OPTION':     0.5,
    'RC9_OPTION':     0.5,
    'RC10_OPTION':    0.5,
    'FS_THR_ENABLE':  0.5,
    'FS_THR_VALUE':   10.0,
    'PILOT_THR_FILT': 0.5,
}

def verify_rc_aux_failsafe_config(traj, env_info, task_info):
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

    passed = score >= 70
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }