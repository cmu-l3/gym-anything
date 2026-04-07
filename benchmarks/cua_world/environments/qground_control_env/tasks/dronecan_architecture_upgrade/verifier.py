#!/usr/bin/env python3
"""Verifier for dronecan_architecture_upgrade task.

Checks all 8 target parameters via pymavlink values recorded in export_result.sh.

Required values:
  CAN_P1_DRIVER   = 1    (default was 0)
  CAN_P2_DRIVER   = 2    (default was 0)
  CAN_D1_PROTOCOL = 1    (default was 0)
  CAN_D2_PROTOCOL = 1    (default was 0)
  GPS1_TYPE       = 9    (default was 1)
  GPS2_TYPE       = 9    (default was 0)
  BATT_MONITOR    = 8    (default was 4)
  NTF_LED_TYPES   = 231  (default was 199)

Scoring (100 pts total, pass = 75):
  Each parameter is worth 12.5 points. 
  A perfect score is 100. Passing requires at least 6 correct parameters (75 pts).
  Tolerance is strict (±0.2) since these are essentially integer enums.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Define targets and points
REQUIRED_PARAMS = {
    'CAN_P1_DRIVER':   (1.0,   12.5),
    'CAN_P2_DRIVER':   (2.0,   12.5),
    'CAN_D1_PROTOCOL': (1.0,   12.5),
    'CAN_D2_PROTOCOL': (1.0,   12.5),
    'GPS1_TYPE':       (9.0,   12.5),
    'GPS2_TYPE':       (9.0,   12.5),
    'BATT_MONITOR':    (8.0,   12.5),
    'NTF_LED_TYPES':   (231.0, 12.5),
}

TOLERANCE = 0.2


def verify_dronecan_upgrade(traj, env_info, task_info):
    """
    Verify that the 8 DroneCAN parameters were correctly set.
    """
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
    
    # Catch SITL connection failures
    if not params.get('connected', True) and all(params.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read.'
        }

    score = 0.0
    feedback = []
    details = {}

    # Evaluate parameters
    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: Not read (+0.0)')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: Invalid value {actual} (+0.0)')
            continue

        if abs(actual_f - required_val) <= TOLERANCE:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (Need {required_val:.0f}) (+0.0)')

    # Float imprecision handling (ensure exactly 100 for perfect)
    score = round(score, 1)
    if score > 99.0:
        score = 100

    passed = score >= 75.0
    
    return {
        'passed': passed,
        'score': int(score),
        'feedback': ' | '.join(feedback),
        'details': details
    }