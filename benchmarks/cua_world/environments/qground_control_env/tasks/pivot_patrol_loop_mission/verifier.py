#!/usr/bin/env python3
"""Verifier for pivot_patrol_loop_mission task.

Checks that the agent created a QGC mission plan containing:
- At least 4 NAV_WAYPOINTs matching the target coordinates
- A DO_CHANGE_SPEED command
- A DO_JUMP command with repeat count ~3
- An RTL command
- Waypoint altitudes in the specified range

Scoring (100 pts total, pass = 75):
  10  File exists at expected path
   5  File modified during task (anti-gaming)
  15  >= 4 NAV_WAYPOINT items found
  10  Waypoints match target coordinates (+- 0.005 deg)
  20  DO_JUMP (cmd 177) present
  10  DO_JUMP repeat == 3 (+- 1)
  15  DO_CHANGE_SPEED (cmd 178) present
  10  RTL (cmd 20) present
   5  Patrol altitude in [30, 50] m
"""

import json
import os
import tempfile
import math

# MAVLink Command IDs
CMD_WAYPOINT = 16
CMD_RTL = 20
CMD_DO_JUMP = 177
CMD_DO_CHANGE_SPEED = 178

TARGET_WPS = [
    (-35.3625, 149.1645),
    (-35.3625, 149.1665),
    (-35.3645, 149.1665),
    (-35.3645, 149.1645)
]

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

def _get_item_coords(item):
    """Extract latitude (params[4]) and longitude (params[5])."""
    params = item.get('params', [])
    if len(params) >= 6 and params[4] is not None and params[5] is not None:
        try:
            return float(params[4]), float(params[5])
        except (TypeError, ValueError):
            pass
    return None, None

def _dist(p1, p2):
    return math.sqrt((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)

def verify_pivot_patrol_loop_mission(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Get the export result
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
        feedback.append('Plan file exists (+10)')
        details['file_exists'] = True
    else:
        feedback.append('Plan file not found (+0)')
        details['file_exists'] = False
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    # --- Check 2: Modified during task (5 pts) ---
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File modified during task (+5)')
        details['modified'] = True
    else:
        feedback.append('File not modified during task (+0)')
        details['modified'] = False

    # --- Parse the plan file ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e} (+0 for remaining checks)')
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    items = plan.get('mission', {}).get('items', [])
    details['item_count'] = len(items)

    # Segregate items by command
    waypoints = [it for it in items if it.get('command') == CMD_WAYPOINT]
    jumps = [it for it in items if it.get('command') == CMD_DO_JUMP]
    speeds = [it for it in items if it.get('command') == CMD_DO_CHANGE_SPEED]
    rtls = [it for it in items if it.get('command') == CMD_RTL]

    details['waypoint_count'] = len(waypoints)
    details['jump_count'] = len(jumps)
    details['speed_count'] = len(speeds)
    details['rtl_count'] = len(rtls)

    # --- Check 3: >= 4 NAV_WAYPOINTs (15 pts) ---
    if len(waypoints) >= 4:
        score += 15
        feedback.append(f'Found {len(waypoints)} NAV_WAYPOINT items (+15)')
    else:
        feedback.append(f'Found {len(waypoints)} NAV_WAYPOINT items (need >= 4) (+0/15)')

    # --- Check 4: Waypoints match target coordinates (10 pts) ---
    matched_targets = 0
    for tgt in TARGET_WPS:
        min_d = 999
        for wp in waypoints:
            lat, lon = _get_item_coords(wp)
            if lat is not None and lon is not None:
                d = _dist(tgt, (lat, lon))
                if d < min_d:
                    min_d = d
        if min_d <= 0.005:
            matched_targets += 1
    
    details['matched_targets'] = matched_targets
    if matched_targets >= 3:
        score += 10
        feedback.append(f'Waypoints matched target coordinates ({matched_targets}/4) (+10)')
    else:
        feedback.append(f'Waypoints did not match targets ({matched_targets}/4 matched) (+0/10)')

    # --- Check 5 & 6: DO_JUMP (20 + 10 pts) ---
    if len(jumps) > 0:
        score += 20
        feedback.append('DO_JUMP command found (+20)')
        
        # Check repeat count
        jump_params = jumps[0].get('params', [])
        # param 2 (index 1) is the repeat count
        if len(jump_params) >= 2 and jump_params[1] is not None:
            try:
                repeat_count = float(jump_params[1])
                details['jump_repeat'] = repeat_count
                if 2.0 <= repeat_count <= 4.0:
                    score += 10
                    feedback.append(f'DO_JUMP repeat count = {repeat_count:.0f} (+10)')
                else:
                    feedback.append(f'DO_JUMP repeat count = {repeat_count:.0f} (expected 3) (+0/10)')
            except (ValueError, TypeError):
                feedback.append('DO_JUMP repeat count invalid (+0/10)')
        else:
            feedback.append('DO_JUMP repeat count not set (+0/10)')
    else:
        feedback.append('DO_JUMP command NOT found (+0/30)')

    # --- Check 7: DO_CHANGE_SPEED (15 pts) ---
    if len(speeds) > 0:
        score += 15
        feedback.append(f'DO_CHANGE_SPEED command found ({len(speeds)} instances) (+15)')
    else:
        feedback.append('DO_CHANGE_SPEED command NOT found (+0/15)')

    # --- Check 8: RTL (10 pts) ---
    if len(rtls) > 0:
        score += 10
        feedback.append('RTL command found (+10)')
    else:
        feedback.append('RTL command NOT found (+0/10)')

    # --- Check 9: Altitude (5 pts) ---
    alt_ok_count = 0
    for wp in waypoints:
        alt = _get_item_altitude(wp)
        if alt is not None and 30 <= alt <= 50:
            alt_ok_count += 1
            
    if len(waypoints) > 0 and alt_ok_count >= len(waypoints) / 2:
        score += 5
        feedback.append('Majority of waypoints at correct altitude [30, 50] m (+5)')
    else:
        feedback.append(f'Waypoint altitudes not in target range ({alt_ok_count}/{len(waypoints)} correct) (+0/5)')

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }