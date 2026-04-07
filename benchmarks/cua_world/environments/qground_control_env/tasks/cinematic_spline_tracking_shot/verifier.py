#!/usr/bin/env python3
"""Verifier for cinematic_spline_tracking_shot task.

The agent must create a cinematic flight plan using advanced MAVLink commands.
Requirements:
- Plan saved at /home/ga/Documents/QGC/river_tracking_shot.plan
- File created/modified during task
- Takeoff (22) and RTL (20) present
- DO_CHANGE_SPEED (178) present with param2 == 4.0
- DO_MOUNT_CONTROL (205) present with param1 == -15.0
- NAV_SPLINE_WAYPOINT (82) used for at least 4 waypoints
- Spline waypoint altitudes set to 25.0

Scoring (100 pts total, pass = 75):
  10  File exists and modified during task
  10  Takeoff and RTL present
  15  DO_CHANGE_SPEED correctly configured
  15  DO_MOUNT_CONTROL correctly configured
  35  Spline curve (NAV_SPLINE_WAYPOINT) used for the flight path
  15  Altitude correct for all spline points
"""

import json
import os
import tempfile


def verify_cinematic_spline_tracking_shot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Copy the result JSON from the container
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

    # --- Check 1: File Exists & Modified (10 pts) ---
    if result.get('file_found', False) and result.get('modified_during_task', False):
        score += 10
        feedback.append('Plan file exists and was created/modified during task (+10)')
    elif result.get('file_found', False):
        feedback.append('Plan file exists but was NOT modified during the task (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}
    else:
        feedback.append('Plan file not found at the expected location (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Parse the plan file ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e} (+0 for remaining checks)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    details['total_items'] = len(items)

    # --- Check 2: Takeoff and RTL (10 pts) ---
    has_takeoff = any(i.get('command') == 22 for i in items)
    has_rtl = any(i.get('command') == 20 for i in items)
    
    if has_takeoff and has_rtl:
        score += 10
        feedback.append('Takeoff and RTL commands present (+10)')
    else:
        feedback.append(f'Missing bounding commands: Takeoff={has_takeoff}, RTL={has_rtl} (+0)')

    # --- Check 3: DO_CHANGE_SPEED (15 pts) ---
    speed_cmds = [i for i in items if i.get('command') == 178]
    has_correct_speed = False
    for cmd in speed_cmds:
        params = cmd.get('params', [])
        # In QGC, param 2 (index 1) is usually the speed value, but we check all to be robust
        if 4.0 in params:
            has_correct_speed = True
            break

    if has_correct_speed:
        score += 15
        feedback.append('DO_CHANGE_SPEED properly configured to 4 m/s (+15)')
    else:
        feedback.append('DO_CHANGE_SPEED not found or not set to 4 m/s (+0)')

    # --- Check 4: DO_MOUNT_CONTROL (15 pts) ---
    gimbal_cmds = [i for i in items if i.get('command') == 205]
    has_correct_gimbal = False
    for cmd in gimbal_cmds:
        params = cmd.get('params', [])
        # MAVLink spec param 1 (index 0) is pitch. Check for -15 degrees or centidegrees
        if -15.0 in params or -1500.0 in params:
            has_correct_gimbal = True
            break

    if has_correct_gimbal:
        score += 15
        feedback.append('DO_MOUNT_CONTROL properly configured to -15 pitch (+15)')
    else:
        feedback.append('DO_MOUNT_CONTROL not found or not set to -15 pitch (+0)')

    # --- Check 5: NAV_SPLINE_WAYPOINT (35 pts) ---
    spline_cmds = [i for i in items if i.get('command') == 82]
    num_splines = len(spline_cmds)
    details['num_spline_waypoints'] = num_splines

    if num_splines >= 4:
        score += 35
        feedback.append(f'Spline waypoints used ({num_splines} found) (+35)')
    elif num_splines > 0:
        score += 10
        feedback.append(f'Spline waypoints partially used ({num_splines} found, need >=4) (+10)')
    else:
        feedback.append('Standard waypoints used instead of Spline waypoints (+0)')

    # --- Check 6: Spline Altitude = 25m (15 pts) ---
    correct_alts = 0
    for cmd in spline_cmds:
        alt = cmd.get('Altitude')
        if alt is None:
            params = cmd.get('params', [])
            if len(params) > 6 and params[6] is not None:
                alt = params[6]
        
        if alt is not None:
            try:
                if abs(float(alt) - 25.0) < 1.0:
                    correct_alts += 1
            except (ValueError, TypeError):
                pass
                
    if num_splines > 0 and correct_alts == num_splines:
        score += 15
        feedback.append('Altitude correctly set to 25m for all spline points (+15)')
    elif num_splines > 0 and correct_alts > 0:
        score += 7
        feedback.append(f'Altitude correct for {correct_alts}/{num_splines} spline points (+7)')
    else:
        feedback.append('Altitude not set correctly for spline waypoints (+0)')

    # Evaluate final pass/fail
    passed = score >= 75

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }