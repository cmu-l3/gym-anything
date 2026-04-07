#!/usr/bin/env python3
"""Verifier for crop_spray_speed_mission task.

The agent must create a QGC mission plan with specific commands and parameters:
  - Takeoff (cmd=22)
  - >= 2 DO_CHANGE_SPEED commands (cmd=178), one with speed <= 4.0, one >= 7.0
  - >= 4 NAV_WAYPOINTs (cmd=16) with altitude in [5.0, 12.0] for the spray passes
  - RTL (cmd=20)

Scoring (100 pts total, pass = 75):
  10  File exists
   5  File modified during task
  10  Takeoff command present
  20  >= 2 DO_CHANGE_SPEED commands (10 pts for exactly 1)
  10  Spray speed value correct (params[1] <= 4.0)
  10  Transit speed value correct (params[1] >= 7.0)
  20  >= 4 low-altitude waypoints (10 pts for 2-3)
  15  RTL command present
"""

import json
import os
import tempfile


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


def verify_crop_spray_speed_mission(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    spray_speed_max = metadata.get('spray_speed_max', 4.0)
    transit_speed_min = metadata.get('transit_speed_min', 7.0)
    spray_alt_min = metadata.get('spray_alt_min', 5.0)
    spray_alt_max = metadata.get('spray_alt_max', 12.0)

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

    # --- Check 1: File exists (10 pts) ---
    file_found = result.get('file_found', False)
    if file_found:
        score += 10
        feedback.append('Mission plan file exists (+10)')
    else:
        feedback.append('Mission plan file not found at expected path (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 2: Modified during task (5 pts) ---
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File created/modified during task (+5)')
    else:
        feedback.append('File not created/modified during task (+0)')

    # --- Parse plan ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Cannot parse mission plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    details['item_count'] = len(items)

    takeoff_cmds = []
    speed_cmds = []
    waypoints = []
    rtl_cmds = []

    for item in items:
        cmd = item.get('command')
        if cmd == 22:   # NAV_TAKEOFF
            takeoff_cmds.append(item)
        elif cmd == 178:  # DO_CHANGE_SPEED
            speed_cmds.append(item)
        elif cmd == 16:   # NAV_WAYPOINT
            waypoints.append(item)
        elif cmd == 20:   # NAV_RETURN_TO_LAUNCH
            rtl_cmds.append(item)

    # --- Check 3: Takeoff command present (10 pts) ---
    if len(takeoff_cmds) > 0:
        score += 10
        feedback.append('Takeoff command found (+10)')
    else:
        feedback.append('No Takeoff command found (+0)')

    # --- Check 4: DO_CHANGE_SPEED count (20 pts) ---
    num_speed_cmds = len(speed_cmds)
    details['speed_cmd_count'] = num_speed_cmds
    if num_speed_cmds >= 2:
        score += 20
        feedback.append(f'Found {num_speed_cmds} DO_CHANGE_SPEED commands (+20)')
    elif num_speed_cmds == 1:
        score += 10
        feedback.append('Found 1 DO_CHANGE_SPEED command (expected >=2) (+10)')
    else:
        feedback.append('No DO_CHANGE_SPEED commands found (+0)')

    # --- Check 5 & 6: Speed command values (10 pts each) ---
    has_spray_speed = False
    has_transit_speed = False
    details['speed_values_found'] = []

    for scmd in speed_cmds:
        params = scmd.get('params', [])
        if len(params) >= 2 and params[1] is not None:
            try:
                speed_val = float(params[1])
                details['speed_values_found'].append(speed_val)
                if speed_val <= spray_speed_max:
                    has_spray_speed = True
                if speed_val >= transit_speed_min:
                    has_transit_speed = True
            except (ValueError, TypeError):
                pass

    if has_spray_speed:
        score += 10
        feedback.append(f'Spray speed (<= {spray_speed_max} m/s) properly configured (+10)')
    else:
        feedback.append('No valid spray speed configuration found (+0)')

    if has_transit_speed:
        score += 10
        feedback.append(f'Transit speed (>= {transit_speed_min} m/s) properly configured (+10)')
    else:
        feedback.append('No valid transit speed configuration found (+0)')

    # --- Check 7: Low-altitude spray waypoints (20 pts) ---
    low_alt_wps = []
    for wp in waypoints:
        alt = _get_item_altitude(wp)
        if alt is not None and spray_alt_min <= alt <= spray_alt_max:
            low_alt_wps.append(wp)

    num_low_alt_wps = len(low_alt_wps)
    details['low_alt_waypoint_count'] = num_low_alt_wps
    if num_low_alt_wps >= 4:
        score += 20
        feedback.append(f'Found {num_low_alt_wps} valid low-altitude spray waypoints (+20)')
    elif num_low_alt_wps >= 2:
        score += 10
        feedback.append(f'Found {num_low_alt_wps} low-altitude spray waypoints (expected >=4) (+10)')
    else:
        feedback.append('Did not find enough low-altitude spray waypoints (+0)')

    # --- Check 8: RTL command present (15 pts) ---
    if len(rtl_cmds) > 0:
        score += 15
        feedback.append('RTL command found (+15)')
    else:
        feedback.append('No RTL command found (+0)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }