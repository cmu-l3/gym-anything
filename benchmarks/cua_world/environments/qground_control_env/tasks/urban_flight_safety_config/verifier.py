#!/usr/bin/env python3
"""
Verifier for urban_flight_safety_config task.

Checks all 7 safety parameters via pymavlink values recorded in export_result.sh.

Required values (all differ from factory defaults):
  GPS_SATS_MIN   = 12    (default: 6)   [15 pts]
  GPS_HDOP_GOOD  = 100   (default: 140) [15 pts]
  COMPASS_USE    = 0     (default: 1)   [10 pts]
  COMPASS_USE2   = 0     (default: 1)   [10 pts]
  COMPASS_USE3   = 0     (default: 1)   [10 pts]
  EK3_SRC1_YAW   = 2     (default: 1)   [20 pts]
  DISARM_DELAY   = 5     (default: 10)  [20 pts]

Scoring (100 pts total, pass threshold = 70)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_PARAMS = {
    'GPS_SATS_MIN':  (12.0, 15),
    'GPS_HDOP_GOOD': (100.0, 15),
    'COMPASS_USE':   (0.0,  10),
    'COMPASS_USE2':  (0.0,  10),
    'COMPASS_USE3':  (0.0,  10),
    'EK3_SRC1_YAW':  (2.0,  20),
    'DISARM_DELAY':  (5.0,  20),
}

# Small float tolerance for safety
TOLERANCE = 0.4

def verify_urban_flight_safety_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Copy the result JSON from the container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read or parse export result JSON: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # If SITL was completely unreachable, report immediately
    if not result.get('connected', True) and all(result.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL vehicle not reachable during export. No parameters could be verified.'
        }

    score = 0
    feedback = []
    details = {}

    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = result.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: value missing/not read (+0/{pts})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts})')
            continue

        # Check if actual is within tolerance of the required float value
        if abs(actual_f - required_val) <= TOLERANCE:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (needed {required_val:.0f}) (+0/{pts})')

    # Pass condition: threshold is 70 points
    passed = score >= 70
    
    if passed:
        feedback_str = "SUCCESS: " + " | ".join(feedback)
    else:
        feedback_str = "FAILED: " + " | ".join(feedback)

    return {
        'passed': passed,
        'score': score,
        'feedback': feedback_str,
        'details': details
    }