#!/usr/bin/env python3
"""Verifier for wildlife_silent_flight_tuning task.

Checks 6 acoustic mitigation parameters via pymavlink values recorded in export_result.sh.

Required values (all different from aggressive factory defaults):
  MOT_SPIN_MAX    = 0.80   (default ~ 0.95)
  ATC_ACCEL_P_MAX = 40000  (default ~ 110000)
  ATC_ACCEL_R_MAX = 40000  (default ~ 110000)
  ATC_ACCEL_Y_MAX = 15000  (default ~ 27000)
  WPNAV_ACCEL     = 100    (default ~ 250)
  ANGLE_MAX       = 2500   (default ~ 4500)

Scoring (100 pts total, pass = 68):
  16 pts for MOT_SPIN_MAX
  17 pts for ATC_ACCEL_P_MAX
  17 pts for ATC_ACCEL_R_MAX
  17 pts for ATC_ACCEL_Y_MAX
  16 pts for WPNAV_ACCEL
  17 pts for ANGLE_MAX
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wildlife_silent_flight_tuning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {})

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

    if not result.get('connected', True) and all(result.get(p) is None for p in required_params.keys()):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read from flight controller'
        }

    score = 0
    feedback = []
    details = {}

    for param_name, config in required_params.items():
        required_val = config['value']
        pts = config['points']
        tol = config['tolerance']
        
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

        if abs(actual_f - required_val) <= tol:
            score += pts
            # Use appropriate formatting depending on whether it's the small float or large int
            if "MOT_SPIN" in param_name:
                feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{pts})')
            else:
                feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            if "MOT_SPIN" in param_name:
                feedback.append(f'{param_name}={actual_f:.2f} (need {required_val:.2f}) (+0/{pts})')
            else:
                feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    # Pass threshold is 68 (requires at least 4 out of 6 parameters to be correct)
    passed = score >= 68
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }