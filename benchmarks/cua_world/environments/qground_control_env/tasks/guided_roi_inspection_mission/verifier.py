#!/usr/bin/env python3
"""Verifier for guided_roi_inspection_mission task.

The agent must plan an inspection mission:
1. Takeoff command
2. DO_SET_ROI (-35.3600, 149.1680, 25m)
3. LOITER_TURNS (radius 30m, altitude 50m, turns >= 2)
4. RTL command

Scoring (100 pts total, pass threshold = 70):
  10  File exists
   5  File modified during task
  10  Takeoff present
  10  ROI command present
  10  ROI latitude correct
   5  ROI longitude correct
   5  ROI altitude reasonable
  10  LOITER_TURNS present
  10  Orbit radius correct
  10  Orbit turns correct
  10  Orbit altitude correct
   5  RTL present
"""

import json
import os
import tempfile


def _get_command(item):
    return item.get('command') or item.get('Command', -1)


def _get_params(item):
    return item.get('params') or item.get('Params', [])


def _get_coordinate_field(item, index):
    """Fallback for reading coordinate arrays if params array is missing."""
    coord = item.get('coordinate') or item.get('Coordinate')
    if isinstance(coord, list) and len(coord) > index:
        return coord[index]
    return None


def verify_guided_roi_inspection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Expected values
    exp_lat = metadata.get('roi_lat', -35.3600)
    exp_lon = metadata.get('roi_lon', 149.1680)
    
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

    # --- 1. File exists (10 pts) ---
    if result.get('file_found', False):
        score += 10
        feedback.append('Plan file exists (+10)')
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- 2. Modified during task (5 pts) ---
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File modified during task (+5)')
    else:
        feedback.append('File not modified during task (+0)')

    # --- Parse plan ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str) and plan_content_raw:
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
        try:
            plan = json.loads(plan_content_raw)
        except Exception as e:
            plan = {}
    elif isinstance(plan_content_raw, dict):
        plan = plan_content_raw
    else:
        plan = {}

    items = plan.get('mission', {}).get('items', [])
    if not items and 'items' in plan:
        items = plan['items']
        
    details['item_count'] = len(items)

    # Search for commands
    takeoff_found = any(_get_command(i) == 22 for i in items)
    roi_items = [i for i in items if _get_command(i) in (201, 195)]
    loiter_items = [i for i in items if _get_command(i) == 18]
    rtl_found = any(_get_command(i) == 20 for i in items)

    # --- 3. Takeoff present (10 pts) ---
    if takeoff_found:
        score += 10
        feedback.append('Takeoff command found (+10)')
    else:
        feedback.append('No Takeoff command found (+0)')

    # --- 4. ROI present (10 pts) ---
    if roi_items:
        score += 10
        feedback.append('ROI command found (+10)')
    else:
        feedback.append('No ROI command found (+0)')

    # --- 5, 6, 7. ROI params (10, 5, 5 pts) ---
    roi_lat_ok = False
    roi_lon_ok = False
    roi_alt_ok = False
    
    for roi in roi_items:
        params = _get_params(roi)
        
        # Lat
        lat = params[4] if len(params) > 4 else _get_coordinate_field(roi, 0)
        if lat is not None:
            try:
                if abs(float(lat) - exp_lat) <= 0.002:
                    roi_lat_ok = True
            except (ValueError, TypeError): pass
            
        # Lon
        lon = params[5] if len(params) > 5 else _get_coordinate_field(roi, 1)
        if lon is not None:
            try:
                if abs(float(lon) - exp_lon) <= 0.002:
                    roi_lon_ok = True
            except (ValueError, TypeError): pass

        # Alt
        alt = params[6] if len(params) > 6 else _get_coordinate_field(roi, 2)
        if alt is None:
            alt = roi.get('Altitude')
        if alt is not None:
            try:
                if 15 <= float(alt) <= 35:
                    roi_alt_ok = True
            except (ValueError, TypeError): pass

    if roi_lat_ok:
        score += 10
        feedback.append('ROI latitude correct (+10)')
    else:
        feedback.append('ROI latitude incorrect (+0)')

    if roi_lon_ok:
        score += 5
        feedback.append('ROI longitude correct (+5)')
    else:
        feedback.append('ROI longitude incorrect (+0)')

    if roi_alt_ok:
        score += 5
        feedback.append('ROI altitude reasonable (+5)')
    else:
        feedback.append('ROI altitude incorrect (+0)')

    # --- 8. LOITER_TURNS present (10 pts) ---
    if loiter_items:
        score += 10
        feedback.append('LOITER_TURNS command found (+10)')
    else:
        feedback.append('No LOITER_TURNS command found (+0)')

    # --- 9, 10, 11. Loiter params (10, 10, 10 pts) ---
    radius_ok = False
    turns_ok = False
    orbit_alt_ok = False
    
    for loit in loiter_items:
        params = _get_params(loit)
        
        # Radius
        radius = params[2] if len(params) > 2 else loit.get('Radius')
        if radius is not None:
            try:
                if 20 <= abs(float(radius)) <= 40:
                    radius_ok = True
            except (ValueError, TypeError): pass
            
        # Turns
        turns = params[0] if len(params) > 0 else loit.get('Turns')
        if turns is not None:
            try:
                if float(turns) >= 2:
                    turns_ok = True
            except (ValueError, TypeError): pass
            
        # Altitude
        alt = params[6] if len(params) > 6 else _get_coordinate_field(loit, 2)
        if alt is None:
            alt = loit.get('Altitude')
        if alt is not None:
            try:
                if 40 <= float(alt) <= 65:
                    orbit_alt_ok = True
            except (ValueError, TypeError): pass

    if radius_ok:
        score += 10
        feedback.append('Orbit radius correct (+10)')
    else:
        feedback.append('Orbit radius incorrect (+0)')
        
    if turns_ok:
        score += 10
        feedback.append('Orbit turns correct (+10)')
    else:
        feedback.append('Orbit turns incorrect (+0)')
        
    if orbit_alt_ok:
        score += 10
        feedback.append('Orbit altitude correct (+10)')
    else:
        feedback.append('Orbit altitude incorrect (+0)')

    # --- 12. RTL present (5 pts) ---
    if rtl_found:
        score += 5
        feedback.append('RTL command found (+5)')
    else:
        feedback.append('No RTL command found (+0)')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }