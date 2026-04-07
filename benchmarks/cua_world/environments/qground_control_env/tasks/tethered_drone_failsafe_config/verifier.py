#!/usr/bin/env python3
"""Verifier for tethered_drone_failsafe_config task.

Checks that the agent set the live parameters securely restricting a drone to a physical tether
and that they exported the config file using QGroundControl.

Required parameters:
  FENCE_ALT_MAX  = 45
  FENCE_RADIUS   = 10
  FENCE_ENABLE   = 1
  FENCE_ACTION   = 3
  RTL_ALT        = 0
  WPNAV_SPEED_UP = 100
  FS_BATT_ENABLE = 0 (or BATT_FS_LOW_ACT = 0)

Scoring (100 pts total, pass = 70):
  15  FENCE_ALT_MAX == 45
  15  FENCE_RADIUS == 10
  15  FENCE_ENABLE == 1
  10  FENCE_ACTION == 3
  15  RTL_ALT == 0
  10  WPNAV_SPEED_UP == 100
  10  FS_BATT_ENABLE == 0
  10  tether_config.params exported during task
"""

import json
import os
import tempfile

def check_param(params, name, expected, pts, feedback, tol=0.5):
    val = params.get(name)
    if val is not None:
        try:
            val_f = float(val)
            if abs(val_f - expected) <= tol:
                feedback.append(f"{name}={val_f:.0f} ✓ (+{pts})")
                return pts
            else:
                feedback.append(f"{name}={val_f:.0f} (need {expected}) (+0/{pts})")
        except (TypeError, ValueError):
            feedback.append(f"{name}=invalid (+0/{pts})")
    else:
        feedback.append(f"{name}: not read (+0/{pts})")
    return 0

def verify_tether_failsafe(traj, env_info, task_info):
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

    score = 0
    feedback = []
    details = {}
    params = result.get('params', {})

    if not result.get('connected', True) and not any(v is not None for v in params.values()):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read.'
        }

    # Parameter Checks
    score += check_param(params, 'FENCE_ALT_MAX', 45.0, 15, feedback)
    score += check_param(params, 'FENCE_RADIUS', 10.0, 15, feedback)
    score += check_param(params, 'FENCE_ENABLE', 1.0, 15, feedback)
    score += check_param(params, 'FENCE_ACTION', 3.0, 10, feedback)
    score += check_param(params, 'RTL_ALT', 0.0, 15, feedback)
    score += check_param(params, 'WPNAV_SPEED_UP', 100.0, 10, feedback)

    # Battery Failsafe Check (either parameter name)
    batt_val = params.get('FS_BATT_ENABLE')
    if batt_val is None:
        batt_val = params.get('BATT_FS_LOW_ACT')
        
    if batt_val is not None:
        try:
            if abs(float(batt_val) - 0.0) <= 0.5:
                score += 10
                feedback.append("Battery failsafe disabled ✓ (+10)")
            else:
                feedback.append(f"Battery failsafe={float(batt_val):.0f} (need 0) (+0/10)")
        except (TypeError, ValueError):
            feedback.append("Battery failsafe invalid (+0/10)")
    else:
        feedback.append("Battery failsafe not read (+0/10)")

    # Config Export Check
    file_found = result.get('file_found', False)
    file_modified = result.get('file_modified', False)
    details['file_found'] = file_found
    details['file_modified'] = file_modified

    if file_found and file_modified:
        score += 10
        feedback.append("tether_config.params exported successfully (+10)")
    elif file_found:
        feedback.append("tether_config.params found but not modified during task (+0/10)")
    else:
        feedback.append("tether_config.params not exported (+0/10)")

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }