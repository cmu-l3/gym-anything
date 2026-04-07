#!/usr/bin/env python3
"""Verifier for disaster_comm_relay_deployment task.

Checks both parameter settings (failsafes) and the mission plan file.

Required Params:
  FS_THR_ENABLE = 2 (Continue with mission in Auto mode)
  FS_GCS_ENABLE = 2 (Continue with mission in Auto mode)

Required Mission Plan Items:
  1. Waypoint (command 16): Lat -35.3580, Lon 149.1660, Alt 110m
  2. Change Heading (command 115): Angle 245
  3. Loiter Time (command 19): 3600 seconds
  4. RTL (command 20)

Scoring (100 pts total, pass = 75):
  15  FS_THR_ENABLE == 2
  15  FS_GCS_ENABLE == 2
  10  Plan file exists & was modified
  15  Waypoint present with correct lat/lon/alt
  15  Change Heading (Condition Yaw) present with correct angle
  15  Loiter Time present with correct duration
  15  RTL present
"""

import json
import os
import tempfile
import math


def _get_item_altitude(item):
    """Extract altitude from a SimpleItem, trying top-level Altitude and params[6]."""
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

def verify_disaster_comm_relay(traj, env_info, task_info):
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

    # --- FAILSAFE PARAMS (30 points) ---
    params = result.get('params', {})
    for p_name in ['FS_THR_ENABLE', 'FS_GCS_ENABLE']:
        actual = params.get(p_name)
        details[p_name] = actual
        if actual is not None and round(float(actual)) == 2:
            score += 15
            feedback.append(f'{p_name}=2 ✓ (+15)')
        else:
            feedback.append(f'{p_name}={actual} (need 2) (+0/15)')

    # --- PLAN FILE CHECKS ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    if file_found and modified:
        score += 10
        feedback.append('Plan file exists and was created/modified (+10)')
    elif file_found:
        score += 5
        feedback.append('Plan file exists but not modified during task (+5/10)')
    else:
        feedback.append('Plan file not found (+0/70 remaining)')
        details['file_found'] = False
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # Parse plan JSON
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Cannot parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    details['total_items'] = len(items)
    
    # Check for specific MAVLink commands
    # 1. Waypoint (cmd 16): Lat -35.3580, Lon 149.1660, Alt 110 (15 pts)
    found_wp = False
    for item in items:
        if item.get('command') == 16:
            p = item.get('params', [])
            if len(p) >= 6:
                lat = p[4]
                lon = p[5]
                alt = _get_item_altitude(item)
                if lat and lon and alt:
                    if (abs(float(lat) - (-35.3580)) < 0.002 and 
                        abs(float(lon) - 149.1660) < 0.002 and 
                        abs(alt - 110) < 5):
                        found_wp = True
                        break
    if found_wp:
        score += 15
        feedback.append('Correct Target Waypoint found ✓ (+15)')
    else:
        feedback.append('Target Waypoint (-35.358, 149.166, 110m) missing or incorrect (+0/15)')

    # 2. Change Heading / Condition Yaw (cmd 115): Angle 245 (15 pts)
    found_yaw = False
    for item in items:
        if item.get('command') == 115:
            p = item.get('params', [])
            if len(p) >= 1 and p[0] is not None:
                if abs(float(p[0]) - 245) < 2:
                    found_yaw = True
                    break
    if found_yaw:
        score += 15
        feedback.append('Condition Yaw (245 deg) found ✓ (+15)')
    else:
        feedback.append('Condition Yaw missing or incorrect angle (+0/15)')

    # 3. Loiter Time (cmd 19): 3600 sec (15 pts)
    found_loiter = False
    for item in items:
        if item.get('command') == 19:
            p = item.get('params', [])
            if len(p) >= 1 and p[0] is not None:
                if abs(float(p[0]) - 3600) < 10:
                    found_loiter = True
                    break
    if found_loiter:
        score += 15
        feedback.append('Loiter Time (3600s) found ✓ (+15)')
    else:
        feedback.append('Loiter Time missing or incorrect duration (+0/15)')

    # 4. RTL (cmd 20) (15 pts)
    found_rtl = any(item.get('command') == 20 for item in items)
    if found_rtl:
        score += 15
        feedback.append('RTL Command found ✓ (+15)')
    else:
        feedback.append('RTL Command missing (+0/15)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }