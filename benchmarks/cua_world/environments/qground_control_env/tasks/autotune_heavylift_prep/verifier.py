#!/usr/bin/env python3
"""Verifier for autotune_heavylift_prep task.

Checks 6 AutoTune and Filter parameters via pymavlink values recorded in export_result.sh.
These values must be updated from their dangerous factory defaults to heavy-lift specs.

Required values:
  AUTOTUNE_AGGR      = 0.05  (default: 0.1)
  AUTOTUNE_AXES      = 3     (default: 7)
  RC7_OPTION         = 17    (default: 0)
  ATC_RAT_RLL_FLTT   = 10    (default: 20)
  ATC_RAT_PIT_FLTT   = 10    (default: 20)
  INS_GYRO_FILTER    = 20    (default: 40)

Scoring (100 pts total, pass = 70):
  AUTOTUNE_AGGR: 20 pts
  AUTOTUNE_AXES: 15 pts
  RC7_OPTION: 15 pts
  ATC_RAT_RLL_FLTT: 15 pts
  ATC_RAT_PIT_FLTT: 15 pts
  INS_GYRO_FILTER: 20 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_autotune_heavylift_prep(traj, env_info, task_info):
    """Verifies if the heavy-lift tuning parameters were correctly applied."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {})
    pass_threshold = metadata.get('pass_threshold', 70)

    # Fallback params if missing in metadata
    if not required_params:
        required_params = {
            "AUTOTUNE_AGGR": {"value": 0.05, "pts": 20, "tolerance": 0.005},
            "AUTOTUNE_AXES": {"value": 3.0, "pts": 15, "tolerance": 0.4},
            "RC7_OPTION": {"value": 17.0, "pts": 15, "tolerance": 0.4},
            "ATC_RAT_RLL_FLTT": {"value": 10.0, "pts": 15, "tolerance": 0.5},
            "ATC_RAT_PIT_FLTT": {"value": 10.0, "pts": 15, "tolerance": 0.5},
            "INS_GYRO_FILTER": {"value": 20.0, "pts": 20, "tolerance": 0.5}
        }

    # Fetch results
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

    params_result = result.get('params', {})
    connected = params_result.get('connected', False)
    
    if not connected:
        # Check if all actual param fields are empty
        if all(params_result.get(p) is None for p in required_params.keys()):
            return {
                'passed': False, 'score': 0,
                'feedback': 'SITL vehicle not reachable during verification export. No parameters could be read.'
            }

    score = 0
    feedback = []
    details = {}

    for param_name, specs in required_params.items():
        expected_val = specs['value']
        pts = specs['pts']
        tol = specs['tolerance']
        
        actual = params_result.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: not read (+0/{pts})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts})')
            continue

        if abs(actual_f - expected_val) <= tol:
            score += pts
            # Formatting floats nicely for display
            display_val = f"{actual_f:.2f}" if abs(actual_f) < 1 else f"{actual_f:.0f}"
            feedback.append(f'{param_name}={display_val} ✓ (+{pts})')
        else:
            display_actual = f"{actual_f:.2f}" if abs(actual_f) < 1 else f"{actual_f:.0f}"
            display_expected = f"{expected_val:.2f}" if abs(expected_val) < 1 else f"{expected_val:.0f}"
            feedback.append(f'{param_name}={display_actual} (need {display_expected}) (+0/{pts})')

    passed = score >= pass_threshold
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }