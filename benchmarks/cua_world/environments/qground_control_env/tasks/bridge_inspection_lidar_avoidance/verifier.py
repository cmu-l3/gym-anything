#!/usr/bin/env python3
"""
Verifier for bridge_inspection_lidar_avoidance task.

Checks that the agent correctly configured 9 parameters related to dual LiDARs
and proximity avoidance.

Required Parameters & Scoring (Total = 100 points):
- RNGFND1_TYPE: 8        (11 pts)
- RNGFND1_ORIENT: 25     (11 pts)
- RNGFND1_MAX_CM: 5000   (11 pts)
- RNGFND2_TYPE: 8        (11 pts)
- RNGFND2_ORIENT: 24     (11 pts)
- RNGFND2_MAX_CM: 1500   (11 pts)
- PRX1_TYPE: 4           (11 pts)
- AVOID_ENABLE: 1        (11 pts)
- AVOID_MARGIN: 2.50     (12 pts)

Pass Threshold: 75 points (Requires most of the workflow to be completed correctly).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Tolerances for floating-point comparisons
TOLERANCES = {
    'AVOID_MARGIN': 0.05,
    'default': 0.5  # For integer-based enums stored as floats in MAVLink
}


def verify_bridge_inspection_lidar_avoidance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {
        'RNGFND1_TYPE': 8.0,
        'RNGFND1_ORIENT': 25.0,
        'RNGFND1_MAX_CM': 5000.0,
        'RNGFND2_TYPE': 8.0,
        'RNGFND2_ORIENT': 24.0,
        'RNGFND2_MAX_CM': 1500.0,
        'PRX1_TYPE': 4.0,
        'AVOID_ENABLE': 1.0,
        'AVOID_MARGIN': 2.50
    })

    # Read exported parameters
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

    if not result.get('connected', True) and all(result.get(p) is None for p in required_params.keys()):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read.'
        }

    score = 0
    feedback = []
    details = {}

    # Define point distribution
    points = {
        'RNGFND1_TYPE': 11,
        'RNGFND1_ORIENT': 11,
        'RNGFND1_MAX_CM': 11,
        'RNGFND2_TYPE': 11,
        'RNGFND2_ORIENT': 11,
        'RNGFND2_MAX_CM': 11,
        'PRX1_TYPE': 11,
        'AVOID_ENABLE': 11,
        'AVOID_MARGIN': 12
    }

    # Evaluate each parameter
    for param_name, required_val in required_params.items():
        actual_val = result.get(param_name)
        pts = points.get(param_name, 0)
        details[param_name] = actual_val

        if actual_val is None:
            feedback.append(f'{param_name}: not found/read (+0/{pts})')
            continue

        try:
            actual_f = float(actual_val)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual_val} (+0/{pts})')
            continue

        tol = TOLERANCES.get(param_name, TOLERANCES['default'])
        
        if abs(actual_f - required_val) <= tol:
            score += pts
            # Format display appropriately (integers vs float)
            if param_name == 'AVOID_MARGIN':
                feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{pts})')
            else:
                feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            if param_name == 'AVOID_MARGIN':
                feedback.append(f'{param_name}={actual_f:.2f} (need {required_val:.2f}) (+0/{pts})')
            else:
                feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    # Overall pass criteria
    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }