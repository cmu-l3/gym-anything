#!/usr/bin/env python3
"""Verifier for indoor_navigation_sensor_setup task.

Checks all 8 required hardware integration parameters via pymavlink values recorded in export_result.sh.

Required values (all differ from defaults):
  RNGFND1_TYPE     = 20   (default: 0)
  RNGFND1_MAX_CM   = 800  (default: 700)
  RNGFND1_MIN_CM   = 10   (default: 20)
  SERIAL2_PROTOCOL = 9    (default: 2)
  SERIAL2_BAUD     = 115  (default: 57)
  FLOW_TYPE        = 2    (default: 0)
  EK3_SRC1_VELXY   = 5    (default: 3)
  EK3_SRC1_POSZ    = 2    (default: 1)

Scoring (100 pts total, pass = 75):
  Each parameter is worth 12.5 points.
"""

import json
import os
import tempfile


def verify_indoor_navigation_sensor_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {
        'RNGFND1_TYPE': 20,
        'RNGFND1_MAX_CM': 800,
        'RNGFND1_MIN_CM': 10,
        'SERIAL2_PROTOCOL': 9,
        'SERIAL2_BAUD': 115,
        'FLOW_TYPE': 2,
        'EK3_SRC1_VELXY': 5,
        'EK3_SRC1_POSZ': 2
    })

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

    if not result.get('connected', True) and all(result.get(p) is None for p in required_params):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read'
        }

    score = 0
    feedback = []
    details = {}

    pts_per_param = 12.5
    
    for param_name, required_val in required_params.items():
        actual = result.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: not read (+0/{pts_per_param})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts_per_param})')
            continue

        # Use an absolute tolerance of 0.4 which is safe for ints/enums represented as floats
        if abs(actual_f - required_val) <= 0.4:
            score += pts_per_param
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts_per_param})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val}) (+0/{pts_per_param})')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }