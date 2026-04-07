#!/usr/bin/env python3
"""Verifier for dual_gps_yaw_config task.

Checks all 8 target parameters via pymavlink values recorded in export_result.sh.

Required values:
  GPS_TYPE2        = 1.0    (Auto)
  GPS_AUTO_SWITCH  = 2.0    (Blend)
  EK3_SRC1_YAW     = 2.0    (GPS)
  COMPASS_ENABLE   = 0.0    (Disabled)
  GPS_POS1_X       = -0.35  (35cm behind CG)
  GPS_POS2_X       =  0.35  (35cm ahead of CG)
  GPS_POS1_Z       = -0.20  (20cm above CG -> NED Down is positive, so above is negative)
  GPS_POS2_Z       = -0.20  (20cm above CG -> negative)

Scoring (100 pts total, pass = 70):
  GPS_TYPE2       : 12.5 pts
  GPS_AUTO_SWITCH : 12.5 pts
  EK3_SRC1_YAW    : 12.5 pts
  COMPASS_ENABLE  : 12.5 pts
  GPS_POS1_X      : 10.0 pts
  GPS_POS2_X      : 10.0 pts
  GPS_POS1_Z      : 15.0 pts
  GPS_POS2_Z      : 15.0 pts
"""

import json
import os
import tempfile


REQUIRED_PARAMS = {
    'GPS_TYPE2':       (1.0,   12.5),
    'GPS_AUTO_SWITCH': (2.0,   12.5),
    'EK3_SRC1_YAW':    (2.0,   12.5),
    'COMPASS_ENABLE':  (0.0,   12.5),
    'GPS_POS1_X':      (-0.35, 10.0),
    'GPS_POS2_X':      (0.35,  10.0),
    'GPS_POS1_Z':      (-0.20, 15.0),
    'GPS_POS2_Z':      (-0.20, 15.0),
}

# Tolerances: wide for enumerations/bools, tighter for precision coordinate entries
TOLERANCES = {
    'GPS_TYPE2':       0.4,
    'GPS_AUTO_SWITCH': 0.4,
    'EK3_SRC1_YAW':    0.4,
    'COMPASS_ENABLE':  0.4,
    'GPS_POS1_X':      0.03,
    'GPS_POS2_X':      0.03,
    'GPS_POS1_Z':      0.03,
    'GPS_POS2_Z':      0.03,
}

def verify_dual_gps_yaw_config(traj, env_info, task_info):
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
            'feedback': 'SITL not reachable during export — no parameters could be read'
        }

    score = 0.0
    feedback = []
    details = {}

    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
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

        tol = TOLERANCES.get(param_name, 0.1)
        
        # Check if the user accidentally inverted the Z axis (very common mistake: putting 0.20 instead of -0.20)
        if param_name in ['GPS_POS1_Z', 'GPS_POS2_Z'] and abs(actual_f - abs(required_val)) <= tol:
            feedback.append(f'{param_name}={actual_f:.2f} (INVERTED Z-AXIS: NED Down is positive, so "above CG" must be negative!) (+0/{pts})')
        # Check if they put X backwards
        elif param_name == 'GPS_POS1_X' and abs(actual_f - 0.35) <= tol:
             feedback.append(f'{param_name}={actual_f:.2f} (INVERTED: "Behind CG" is negative X in NED) (+0/{pts})')
        elif param_name == 'GPS_POS2_X' and abs(actual_f - -0.35) <= tol:
             feedback.append(f'{param_name}={actual_f:.2f} (INVERTED: "Ahead of CG" is positive X in NED) (+0/{pts})')
        # Check for correct value
        elif abs(actual_f - required_val) <= tol:
            score += pts
            if pts.is_integer():
                feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{int(pts)})')
            else:
                feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.2f} (need {required_val:.2f}) (+0/{pts})')

    # Convert score to int, rounding properly
    final_score = int(round(score))
    passed = final_score >= 70

    return {
        'passed': passed,
        'score': final_score,
        'feedback': ' | '.join(feedback),
        'details': details
    }