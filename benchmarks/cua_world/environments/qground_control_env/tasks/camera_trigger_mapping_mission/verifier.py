#!/usr/bin/env python3
"""Verifier for camera_trigger_mapping_mission task.

Checks that the agent created a mapping mission with embedded DO_SET_CAM_TRIGG_DIST commands
and set the navigation speed correctly.

Scoring (100 pts total, pass = 70):
  10  File exists at expected path
  10  File modified during task
  15  >=4 NAV_WAYPOINT items
  15  Waypoint altitudes in [100, 140] m
  20  Camera trigger START command (DO_SET_CAM_TRIGG_DIST with dist ~25m)
  10  Camera trigger STOP command (DO_SET_CAM_TRIGG_DIST with dist = 0m)
  10  RTL command present
  10  WPNAV_SPEED = 800 (±50)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MAV_CMD_NAV_WAYPOINT = 16
MAV_CMD_NAV_RETURN_TO_LAUNCH = 20
MAV_CMD_DO_SET_CAM_TRIGG_DIST = 206

ALT_MIN = 100.0
ALT_MAX = 140.0
SPEED_TARGET = 800.0
SPEED_TOLERANCE = 50.0

def _get_item_altitude(item):
    """Extract altitude from a SimpleItem, trying Altitude field or params[6]."""
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

def verify_camera_trigger_mapping_mission(traj, env_info, task_info):
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
        feedback.append('Plan file exists (+10)')
    else:
        feedback.append('Plan file not found at expected path (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 2: Modified during task (10 pts) ---
    if result.get('modified_during_task', False):
        score += 10
        feedback.append('File modified during task (+10)')
    else:
        feedback.append('File not modified during task (+0)')

    # --- Parse plan content ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Cannot parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    
    waypoints = [it for it in items if it.get('command') == MAV_CMD_NAV_WAYPOINT]
    triggers = [it for it in items if it.get('command') == MAV_CMD_DO_SET_CAM_TRIGG_DIST]
    rtls = [it for it in items if it.get('command') == MAV_CMD_NAV_RETURN_TO_LAUNCH]

    # --- Check 3: >=4 NAV_WAYPOINTs (15 pts) ---
    wp_count = len(waypoints)
    details['waypoint_count'] = wp_count
    if wp_count >= 4:
        score += 15
        feedback.append(f'Found {wp_count} navigation waypoints (+15)')
    elif wp_count > 0:
        score += 5
        feedback.append(f'Found only {wp_count} navigation waypoints (expected >=4) (+5 partial)')
    else:
        feedback.append('No navigation waypoints found (+0)')

    # --- Check 4: Waypoint altitudes in [100, 140] m (15 pts) ---
    if wp_count > 0:
        correct_alts = 0
        for wp in waypoints:
            alt = _get_item_altitude(wp)
            if alt is not None and ALT_MIN <= alt <= ALT_MAX:
                correct_alts += 1
        
        details['correct_alt_waypoints'] = correct_alts
        
        if correct_alts >= 3:
            score += 15
            feedback.append(f'Waypoint altitudes correct ({correct_alts} waypoints ~120m) (+15)')
        elif correct_alts > 0:
            score += 5
            feedback.append(f'Some waypoint altitudes correct ({correct_alts} waypoints ~120m) (+5 partial)')
        else:
            feedback.append('Waypoint altitudes incorrect (expected ~120m) (+0)')
    else:
        feedback.append('No waypoints to check altitude (+0)')

    # --- Check 5: Trigger START command (20 pts) ---
    trigger_starts = 0
    trigger_stops = 0
    for trig in triggers:
        params = trig.get('params', [])
        if len(params) > 0 and params[0] is not None:
            dist = float(params[0])
            if 20.0 <= dist <= 30.0:
                trigger_starts += 1
            elif dist == 0.0:
                trigger_stops += 1

    details['trigger_start_count'] = trigger_starts
    details['trigger_stop_count'] = trigger_stops

    if trigger_starts > 0:
        score += 20
        feedback.append('Camera trigger START command found (~25m) (+20)')
    else:
        feedback.append('Camera trigger START command NOT found (+0)')

    # --- Check 6: Trigger STOP command (10 pts) ---
    if trigger_stops > 0:
        score += 10
        feedback.append('Camera trigger STOP command found (0m) (+10)')
    else:
        feedback.append('Camera trigger STOP command NOT found (+0)')

    # --- Check 7: RTL command present (10 pts) ---
    if len(rtls) > 0:
        score += 10
        feedback.append('RTL command found (+10)')
    else:
        feedback.append('RTL command NOT found (+0)')

    # --- Check 8: WPNAV_SPEED parameter (10 pts) ---
    pymav_params = result.get('params', {})
    speed = pymav_params.get('WPNAV_SPEED')
    details['WPNAV_SPEED'] = speed

    if speed is not None:
        try:
            speed_val = float(speed)
            if abs(speed_val - SPEED_TARGET) <= SPEED_TOLERANCE:
                score += 10
                feedback.append(f'WPNAV_SPEED is correct: {speed_val:.0f} (+10)')
            else:
                feedback.append(f'WPNAV_SPEED is incorrect: {speed_val:.0f} (expected {SPEED_TARGET:.0f}) (+0)')
        except ValueError:
            feedback.append('WPNAV_SPEED value is invalid (+0)')
    else:
        feedback.append('WPNAV_SPEED parameter could not be verified (+0)')

    passed = score >= 70

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }