#!/usr/bin/env python3
"""Verifier for dshot_esc_telemetry_config task.

Checks all 7 target parameters via pymavlink values recorded in export_result.sh.

Required values:
  MOT_PWM_TYPE     = 6    (DShot600)
  SERIAL2_PROTOCOL = 16   (ESC Telemetry)
  SERIAL2_BAUD     = 115  (115200)
  SERVO_BLH_AUTO   = 1    (Enabled)
  SERVO_BLH_POLES  = 28   (28 poles)
  INS_HNTCH_ENABLE = 1    (Enabled)
  INS_HNTCH_MODE   = 3    (ESC Telemetry) - requires reboot to expose

Scoring (100 pts total, pass = 70):
  MOT_PWM_TYPE: 15 pts
  SERIAL2_PROTOCOL: 15 pts
  SERIAL2_BAUD: 14 pts
  SERVO_BLH_AUTO: 14 pts
  SERVO_BLH_POLES: 14 pts
  INS_HNTCH_ENABLE: 14 pts
  INS_HNTCH_MODE: 10 pts
"""

import json
import os
import tempfile


REQUIRED_PARAMS = {
    'MOT_PWM_TYPE':     (6.0,   15),
    'SERIAL2_PROTOCOL': (16.0,  15),
    'SERIAL2_BAUD':     (115.0, 14),
    'SERVO_BLH_AUTO':   (1.0,   14),
    'SERVO_BLH_POLES':  (28.0,  14),
    'INS_HNTCH_ENABLE': (1.0,   14),
    'INS_HNTCH_MODE':   (3.0,   10),
}


def verify_dshot_config(traj, env_info, task_info):
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

    score = 0
    feedback = []
    details = {}

    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual

        if actual is None:
            if param_name == 'INS_HNTCH_MODE':
                feedback.append(f'{param_name}: not found (Did you forget to reboot the vehicle?) (+0/{pts})')
            else:
                feedback.append(f'{param_name}: not read (+0/{pts})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts})')
            continue

        # Exact matching for integers using small tolerance
        if abs(actual_f - required_val) <= 0.2:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }