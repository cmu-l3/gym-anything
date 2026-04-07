#!/usr/bin/env python3
"""Verifier for atmospheric_sniffer_integration task.

Checks that the agent:
1. Set 6 ArduPilot parameters for the sniffer integration.
2. Created a vertical profile mission with a DO_CHANGE_SPEED and a high-altitude waypoint.

Scoring (100 pts total, pass = 75):
  10  SCR_ENABLE = 1
  10  SCR_HEAP_SIZE = 81920
  10  SERIAL4_PROTOCOL = 28
  10  SERIAL4_BAUD = 115
  10  LOG_DISARMED = 1
  10  BRD_BOOT_DELAY = 3000
  10  Plan file exists and was modified during task
  15  DO_CHANGE_SPEED (cmd 178) present with speed ~1.0 m/s
  15  Vertical Waypoint (cmd 16) present with altitude >= 140m
"""

import json
import os
import tempfile


REQUIRED_PARAMS = {
    'SCR_ENABLE':       (1.0,     10),
    'SCR_HEAP_SIZE':    (81920.0, 10),
    'SERIAL4_PROTOCOL': (28.0,    10),
    'SERIAL4_BAUD':     (115.0,   10),
    'LOG_DISARMED':     (1.0,     10),
    'BRD_BOOT_DELAY':   (3000.0,  10),
}


def _get_item_altitude(item):
    """Extract altitude from a SimpleItem, trying Altitude and params[6]."""
    alt = item.get('Altitude')
    if alt is not None:
        try:
            return float(alt)
        except (TypeError, ValueError):
            pass
    params = item.get('params', [])
    if len(params) >= 7 and params[6] is not None:
        try:
            return float(params[6])
        except (TypeError, ValueError):
            pass
    return None


def verify_atmospheric_sniffer_integration(traj, env_info, task_info):
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

    # --- 1. Parameter Checks (60 pts) ---
    params = result.get('params', {})
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

        # Strict tolerance for exact settings
        tol = 0.5 
        if abs(actual_f - required_val) <= tol:
            score += pts
            feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')

    # --- 2. Plan File Exists & Modified (10 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    
    if file_found and modified:
        score += 10
        feedback.append('Plan file exists and was modified (+10)')
    elif file_found:
        feedback.append('Plan file exists but was NOT modified during task (+0)')
    else:
        feedback.append('Plan file not found (+0)')

    # --- 3. Parse Plan Content ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    
    plan = {}
    if file_found:
        try:
            plan = json.loads(plan_content_raw)
        except Exception as e:
            feedback.append(f'Could not parse plan JSON: {e}')

    items = plan.get('mission', {}).get('items', [])
    
    # --- 4. Check DO_CHANGE_SPEED (15 pts) ---
    speed_cmds = [it for it in items if it.get('command') == 178] # 178 = MAV_CMD_DO_CHANGE_SPEED
    speed_correct = False
    
    if speed_cmds:
        for it in speed_cmds:
            # Speed is usually param2 for DO_CHANGE_SPEED, but sometimes param1 depending on QGC version
            params_arr = it.get('params', [])
            if len(params_arr) >= 2:
                # check if param2 is ~1.0
                p2 = params_arr[1]
                if p2 is not None:
                    try:
                        val = float(p2)
                        if 0.5 <= val <= 2.0: # allow ~1.0 m/s
                            speed_correct = True
                    except:
                        pass
        if speed_correct:
            score += 15
            feedback.append('DO_CHANGE_SPEED command found with correct speed (+15)')
        else:
            feedback.append('DO_CHANGE_SPEED command found, but speed not set to 1.0 m/s (+0)')
    else:
        feedback.append('No DO_CHANGE_SPEED (command 178) found (+0)')

    # --- 5. Check High-Altitude Waypoint (15 pts) ---
    waypoints = [it for it in items if it.get('command') == 16] # 16 = NAV_WAYPOINT
    alt_correct = False
    
    if waypoints:
        for it in waypoints:
            alt = _get_item_altitude(it)
            if alt is not None and alt >= 140.0:
                alt_correct = True
                break
        
        if alt_correct:
            score += 15
            feedback.append('Vertical Waypoint found with altitude >= 140m (+15)')
        else:
            feedback.append('Waypoints found, but none reached altitude >= 140m (+0)')
    else:
        feedback.append('No NAV_WAYPOINT (command 16) found (+0)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }