#!/usr/bin/env python3
"""Verifier for field_boundary_inspection task.

Checks that the agent created a multi-command QGC mission plan from scratch.
Required elements:
- Takeoff command (cmd=22)
- >=4 Waypoints (cmd=16)
- 2 Loiter Time commands (cmd=19) with hold times ~30s and ~20s
- Change Speed command (cmd=178) with speed ~3 m/s
- RTL command (cmd=20)
- Waypoint altitudes ~30m

Scoring (100 pts total, pass = 70):
  10  File exists
   5  File modified during task
  12  Takeoff command present
  15  >=4 NAV_WAYPOINT items (partial 8 for 2-3)
  13  Loiter command #1 (>=25s)
  13  Loiter command #2 (>=15s)
  10  DO_CHANGE_SPEED command present
   5  DO_CHANGE_SPEED value in [2, 4] m/s
  12  RTL command present
   5  Waypoint altitudes in [20, 50] m
"""

import json
import os
import tempfile

CMD_TAKEOFF = 22
CMD_WAYPOINT = 16
CMD_LOITER_TIME = 19
CMD_CHANGE_SPEED = 178
CMD_RTL = 20

ALT_MIN = 20.0
ALT_MAX = 50.0


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


def verify_field_boundary_inspection(traj, env_info, task_info):
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

    # --- Check 1: File exists (10 pts) ---
    file_found = result.get('file_found', False)
    if file_found:
        score += 10
        feedback.append('Mission plan file exists (+10)')
    else:
        feedback.append('Mission plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 2: Modified during task (5 pts) ---
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File modified during task (+5)')
    else:
        feedback.append('File not modified during task (+0)')

    # --- Parse plan ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Cannot parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    details['item_count'] = len(items)

    # Separate items by command type
    takeoffs = [it for it in items if it.get('command') == CMD_TAKEOFF]
    waypoints = [it for it in items if it.get('command') == CMD_WAYPOINT]
    loiters = [it for it in items if it.get('command') == CMD_LOITER_TIME]
    speeds = [it for it in items if it.get('command') == CMD_CHANGE_SPEED]
    rtls = [it for it in items if it.get('command') == CMD_RTL]

    # --- Check 3: Takeoff command (12 pts) ---
    if takeoffs:
        score += 12
        feedback.append('Takeoff command found (+12)')
    else:
        feedback.append('No Takeoff command found (+0)')

    # --- Check 4: Waypoints (15 pts) ---
    wp_count = len(waypoints)
    details['waypoint_count'] = wp_count
    if wp_count >= 4:
        score += 15
        feedback.append(f'{wp_count} Waypoints found (+15)')
    elif wp_count >= 2:
        score += 8
        feedback.append(f'{wp_count} Waypoints found (need >=4) (+8 partial)')
    else:
        feedback.append(f'Only {wp_count} Waypoints found (+0)')

    # --- Check 5 & 6: Loiter times (13 + 13 pts) ---
    # Extract hold times from params[0]
    hold_times = []
    for loit in loiters:
        p = loit.get('params', [])
        if len(p) >= 1 and p[0] is not None:
            try:
                hold_times.append(float(p[0]))
            except (TypeError, ValueError):
                pass
    
    hold_times.sort(reverse=True)
    details['loiter_times'] = hold_times

    if len(hold_times) > 0 and hold_times[0] >= 25.0:
        score += 13
        feedback.append(f'Loiter command 1 found (time: {hold_times[0]}s) (+13)')
    else:
        feedback.append('Loiter command >=25s not found (+0)')

    if len(hold_times) > 1 and hold_times[1] >= 15.0:
        score += 13
        feedback.append(f'Loiter command 2 found (time: {hold_times[1]}s) (+13)')
    else:
        feedback.append('Second Loiter command >=15s not found (+0)')

    # --- Check 7 & 8: Change Speed (10 + 5 pts) ---
    speed_vals = []
    for spd in speeds:
        p = spd.get('params', [])
        # QGC stores target speed in params[1] for DO_CHANGE_SPEED
        if len(p) >= 2 and p[1] is not None:
            try:
                speed_vals.append(float(p[1]))
            except (TypeError, ValueError):
                pass

    details['speed_values'] = speed_vals

    if speeds:
        score += 10
        feedback.append('DO_CHANGE_SPEED command found (+10)')
        
        # Check if any speed is in the [2, 4] range (target is 3 m/s)
        correct_speed = any(2.0 <= s <= 4.0 for s in speed_vals)
        if correct_speed:
            score += 5
            feedback.append('DO_CHANGE_SPEED value correct (~3 m/s) (+5)')
        else:
            feedback.append(f'DO_CHANGE_SPEED value incorrect: {speed_vals} (+0)')
    else:
        feedback.append('DO_CHANGE_SPEED command not found (+0/15)')

    # --- Check 9: RTL command (12 pts) ---
    if rtls:
        score += 12
        feedback.append('RTL command found (+12)')
    else:
        feedback.append('RTL command not found (+0)')

    # --- Check 10: Waypoint Altitudes (5 pts) ---
    if waypoints:
        alts = [_get_item_altitude(w) for w in waypoints]
        valid_alts = [a for a in alts if a is not None and ALT_MIN <= a <= ALT_MAX]
        if len(valid_alts) == len(waypoints):
            score += 5
            feedback.append('All waypoint altitudes in [20, 50]m range (+5)')
        else:
            feedback.append(f'Some waypoint altitudes outside [20, 50]m range (+0)')
    else:
        feedback.append('No waypoints to check altitude (+0)')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }