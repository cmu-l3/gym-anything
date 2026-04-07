#!/usr/bin/env python3
"""Verifier for battery_nav_spray_config task.

Checks that the agent correctly configured 10 parameters based on the SOP document.

Parameters and Expected Values:
  BATT_CAPACITY = 5200
  BATT_LOW_VOLT = 21.6
  BATT_CRT_VOLT = 20.4
  BATT_FS_LOW_ACT = 2
  BATT_FS_CRT_ACT = 1
  BATT_LOW_MAH = 1040
  BATT_CRT_MAH = 520
  WPNAV_SPEED = 350
  WPNAV_SPEED_DN = 100
  WPNAV_LOIT_SPEED = 250

Each correctly configured parameter is worth 10 points. Total: 100.
Pass threshold: 70 points (at least 7 parameters correct).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_battery_nav_spray_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {})
    tolerances = metadata.get('tolerances', {})

    # Use defaults if metadata is missing
    if not required_params:
        required_params = {
            'BATT_CAPACITY': 5200.0,
            'BATT_LOW_VOLT': 21.6,
            'BATT_CRT_VOLT': 20.4,
            'BATT_FS_LOW_ACT': 2.0,
            'BATT_FS_CRT_ACT': 1.0,
            'BATT_LOW_MAH': 1040.0,
            'BATT_CRT_MAH': 520.0,
            'WPNAV_SPEED': 350.0,
            'WPNAV_SPEED_DN': 100.0,
            'WPNAV_LOIT_SPEED': 250.0
        }
    if not tolerances:
        tolerances = {
            'BATT_CAPACITY': 50.0, 'BATT_LOW_VOLT': 0.5, 'BATT_CRT_VOLT': 0.5,
            'BATT_FS_LOW_ACT': 0.4, 'BATT_FS_CRT_ACT': 0.4, 'BATT_LOW_MAH': 50.0, 
            'BATT_CRT_MAH': 50.0, 'WPNAV_SPEED': 25.0, 'WPNAV_SPEED_DN': 15.0, 
            'WPNAV_LOIT_SPEED': 25.0
        }

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
    
    if not params.get('connected', True) and all(params.get(p) is None for p in required_params):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read',
            'details': {}
        }

    score = 0
    feedback = []
    details = {}

    pts_per_param = 100.0 / len(required_params)

    for param_name, required_val in required_params.items():
        actual = params.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: not read (+0)')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0)')
            continue

        tol = tolerances.get(param_name, 1.0)
        
        if abs(actual_f - float(required_val)) <= tol:
            score += pts_per_param
            feedback.append(f'{param_name}={actual_f:.1f} ✓ (+{int(pts_per_param)})')
        else:
            feedback.append(f'{param_name}={actual_f:.1f} (need {required_val}) (+0)')

    # Round score to handle floating point issues
    final_score = int(round(score))
    
    # Passing threshold is 70 points
    passed = final_score >= 70
    
    if passed:
        feedback.insert(0, f"✅ Passed ({final_score}/100 pts)")
    else:
        feedback.insert(0, f"❌ Failed ({final_score}/100 pts - need 70)")

    return {
        'passed': passed,
        'score': final_score,
        'feedback': ' | '.join(feedback),
        'details': details
    }