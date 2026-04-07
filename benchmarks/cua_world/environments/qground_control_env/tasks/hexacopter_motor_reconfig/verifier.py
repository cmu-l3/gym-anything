#!/usr/bin/env python3
"""Verifier for hexacopter_motor_reconfig task.

Checks all 8 motor, frame, and battery parameters via pymavlink values.
All defaults differ significantly from the target values.

Required values:
  FRAME_CLASS       = 2         (Hexacopter, default 1)
  MOT_SPIN_ARM      = 0.08      (default 0.10)
  MOT_SPIN_MIN      = 0.12      (default 0.15)
  MOT_BAT_VOLT_MAX  = 25.2      (default 0.0)
  MOT_BAT_VOLT_MIN  = 19.8      (default 0.0)
  MOT_THST_EXPO     = 0.55      (default 0.65)
  MOT_THST_HOVER    = 0.42      (default 0.35)
  BATT_CAPACITY     = 16000     (default 3300)

Scoring (100 pts total, pass = 65):
  FRAME_CLASS      : 15 pts
  MOT_BAT_VOLT_MAX : 13 pts
  MOT_BAT_VOLT_MIN : 13 pts
  MOT_SPIN_ARM     : 12 pts
  MOT_SPIN_MIN     : 12 pts
  MOT_THST_EXPO    : 12 pts
  MOT_THST_HOVER   : 12 pts
  BATT_CAPACITY    : 11 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Dictionary containing target acceptable ranges (min, max), points, and human-readable target
REQUIRED_PARAMS = {
    'FRAME_CLASS':      (1.6, 2.4, 15, "2"),
    # MOT_SPIN_ARM default is 0.10. Must be < 0.095 to score. Target is 0.08.
    'MOT_SPIN_ARM':     (0.06, 0.095, 12, "0.08"),
    'MOT_SPIN_MIN':     (0.10, 0.14, 12, "0.12"),
    'MOT_BAT_VOLT_MAX': (24.8, 25.6, 13, "25.2"),
    'MOT_BAT_VOLT_MIN': (19.4, 20.2, 13, "19.8"),
    'MOT_THST_EXPO':    (0.52, 0.58, 12, "0.55"),
    'MOT_THST_HOVER':   (0.39, 0.45, 12, "0.42"),
    'BATT_CAPACITY':    (15500, 16500, 11, "16000")
}


def verify_hexacopter_motor_reconfig(traj, env_info, task_info):
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
            'feedback': 'SITL not reachable during export — no parameters could be read.'
        }

    score = 0
    feedback = []
    details = {}

    for param_name, (min_val, max_val, pts, target_str) in REQUIRED_PARAMS.items():
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

        if min_val <= actual_f <= max_val:
            score += pts
            # Format cleanly for the feedback string
            if actual_f.is_integer() or actual_f > 100:
                feedback.append(f'{param_name}={int(actual_f)} ✓ (+{pts})')
            else:
                feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{pts})')
        else:
            if actual_f.is_integer() or actual_f > 100:
                feedback.append(f'{param_name}={int(actual_f)} (need {target_str}) (+0/{pts})')
            else:
                feedback.append(f'{param_name}={actual_f:.2f} (need {target_str}) (+0/{pts})')

    passed = score >= 65
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }