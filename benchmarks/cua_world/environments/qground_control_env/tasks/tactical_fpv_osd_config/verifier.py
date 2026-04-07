#!/usr/bin/env python3
"""Verifier for tactical_fpv_osd_config task.

Checks all 16 OSD configuration parameters via pymavlink values.

Scoring (100 pts total, pass = 75):
  System Enable (10 pts): OSD_TYPE==1 (5), OSD1_ENABLE==1 (5)
  Flight Mode (15 pts): EN==1 (5), X==2 (5), Y==1 (5)
  Battery Voltage (15 pts): EN==1 (5), X==2 (5), Y==14 (5)
  Current (15 pts): EN==1 (5), X==22 (5), Y==14 (5)
  RSSI (15 pts): EN==1 (5), X==22 (5), Y==1 (5)
  Clutter disabled (30 pts): OSD1_ALTITUDE_EN==0 (15), OSD1_MESSAGE_EN==0 (15)
"""

import json
import os
import tempfile

PARAM_TARGETS = {
    'OSD_TYPE': (1.0, 5),
    'OSD1_ENABLE': (1.0, 5),
    'OSD1_FLTMODE_EN': (1.0, 5),
    'OSD1_FLTMODE_X': (2.0, 5),
    'OSD1_FLTMODE_Y': (1.0, 5),
    'OSD1_BAT_VOLT_EN': (1.0, 5),
    'OSD1_BAT_VOLT_X': (2.0, 5),
    'OSD1_BAT_VOLT_Y': (14.0, 5),
    'OSD1_CURRENT_EN': (1.0, 5),
    'OSD1_CURRENT_X': (22.0, 5),
    'OSD1_CURRENT_Y': (14.0, 5),
    'OSD1_RSSI_EN': (1.0, 5),
    'OSD1_RSSI_X': (22.0, 5),
    'OSD1_RSSI_Y': (1.0, 5),
    'OSD1_ALTITUDE_EN': (0.0, 15),
    'OSD1_MESSAGE_EN': (0.0, 15)
}


def verify_tactical_fpv_osd_config(traj, env_info, task_info):
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
    
    # Check for complete communication failure
    if not params.get('connected', True) and all(params.get(p) is None for p in PARAM_TARGETS):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read'
        }

    score = 0
    feedback = []
    details = {}

    for param_name, (required_val, pts) in PARAM_TARGETS.items():
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

        tol = 0.4 # Typical floating-point tolerance for integer parameters
        if abs(actual_f - required_val) <= tol:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }