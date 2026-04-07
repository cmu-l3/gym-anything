#!/usr/bin/env python3
"""Verifier for high_altitude_density_tuning task.

Queries the recorded parameter values from the SITL simulation and scores 
them based on the strict requirements provided in the engineering report.

Parameters verified:
  MOT_THST_HOVER   (required: 0.42, points: 18)
  MOT_HOVER_LEARN  (required: 0.0,  points: 16)
  MOT_SPIN_ARM     (required: 0.15, points: 17)
  MOT_SPIN_MIN     (required: 0.17, points: 17)
  ATC_THR_MIX_MAN  (required: 0.1,  points: 16)
  MOT_YAW_HEADROOM (required: 150.0, points: 16)

Total Points: 100
Pass Threshold: 80
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_high_altitude_tuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {})

    # Use a safe temporary file to copy the JSON out of the container
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

    params_data = result.get('params', {})
    
    # Early escape if SITL couldn't be contacted during export
    if not params_data.get('connected', True) and all(params_data.get(p) is None for p in required_params.keys()):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL simulation was not reachable during verification export — no parameters could be read.'
        }

    score = 0
    feedback = []
    details = {}

    for param_name, specs in required_params.items():
        req_val = specs.get('value')
        pts = specs.get('points')
        tol = specs.get('tolerance')
        
        actual_val = params_data.get(param_name)
        details[param_name] = actual_val

        if actual_val is None:
            feedback.append(f'{param_name}: Not read/missing from SITL (+0/{pts})')
            continue

        try:
            actual_float = float(actual_val)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: Invalid value type "{actual_val}" (+0/{pts})')
            continue

        # Check if within tolerance
        if abs(actual_float - req_val) <= tol:
            score += pts
            # Format nicely for floats vs integers
            if req_val.is_integer():
                feedback.append(f'{param_name}={actual_float:.0f} ✓ (+{pts})')
            else:
                feedback.append(f'{param_name}={actual_float:.2f} ✓ (+{pts})')
        else:
            if req_val.is_integer():
                feedback.append(f'{param_name}={actual_float:.0f} (Expected {req_val:.0f}) (+0/{pts})')
            else:
                feedback.append(f'{param_name}={actual_float:.2f} (Expected {req_val:.2f}) (+0/{pts})')

    # Pass logic
    passed = score >= 80

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }