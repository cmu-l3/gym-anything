#!/usr/bin/env python3
"""Verifier for landing_approach_config task.

Checks that the agent created a plan file with the correct MAVLink commands
for a landing approach, and configured the required descent parameters.

Scoring (100 pts total, pass = 75):
  10  Plan file exists
   5  File modified during task
  20  DO_LAND_START (189) present
  20  NAV_LAND (21) present
  15  >=2 descending approach waypoints between DO_LAND_START and LAND
  10  LAND_SPEED == 50
  10  LAND_ALT_LOW == 1000
  10  WPNAV_SPEED_DN == 100
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

def verify_landing_approach(traj, env_info, task_info):
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
    if result.get('file_found', False):
        score += 10
        feedback.append('Plan file exists (+10)')
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 2: Modified during task (5 pts) ---
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File modified during task (+5)')
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
    
    # Identify key commands
    idx_land_start = -1
    idx_land = -1
    
    for i, item in enumerate(items):
        cmd = item.get('command')
        if cmd == 189 and idx_land_start == -1:  # MAV_CMD_DO_LAND_START
            idx_land_start = i
        elif cmd == 21:  # MAV_CMD_NAV_LAND
            idx_land = i

    # --- Check 3: DO_LAND_START present (20 pts) ---
    if idx_land_start != -1:
        score += 20
        feedback.append('DO_LAND_START command (189) present (+20)')
    else:
        feedback.append('DO_LAND_START command (189) NOT found (+0)')

    # --- Check 4: NAV_LAND present (20 pts) ---
    if idx_land != -1:
        score += 20
        feedback.append('NAV_LAND command (21) present (+20)')
    else:
        feedback.append('NAV_LAND command (21) NOT found (+0)')

    # --- Check 5: Descending approach waypoints (15 pts) ---
    if idx_land_start != -1 and idx_land != -1 and idx_land > idx_land_start:
        approach_alts = []
        for i in range(idx_land_start + 1, idx_land):
            item = items[i]
            if item.get('command') == 16:  # NAV_WAYPOINT
                alt = _get_item_altitude(item)
                if alt is not None:
                    approach_alts.append(alt)
        
        details['approach_altitudes'] = approach_alts
        
        if len(approach_alts) >= 2:
            is_descending = all(approach_alts[j] > approach_alts[j+1] for j in range(len(approach_alts)-1))
            if is_descending:
                score += 15
                feedback.append(f'Found {len(approach_alts)} descending approach waypoints {approach_alts} (+15)')
            else:
                feedback.append(f'Approach waypoints found {approach_alts} but they are not strictly descending (+0)')
        else:
            feedback.append(f'Not enough approach waypoints between DO_LAND_START and LAND (found {len(approach_alts)}, need >= 2) (+0)')
    else:
        feedback.append('Could not evaluate approach waypoints (missing or out of order DO_LAND_START / LAND) (+0)')

    # --- Parameters Checks (10 pts each) ---
    params = result.get('params', {})
    
    required = {
        'LAND_SPEED': (50.0, 5.0),
        'LAND_ALT_LOW': (1000.0, 50.0),
        'WPNAV_SPEED_DN': (100.0, 10.0)
    }

    for pname, (req_val, tol) in required.items():
        actual = params.get(pname)
        details[pname] = actual
        if actual is not None:
            try:
                actual_f = float(actual)
                if abs(actual_f - req_val) <= tol:
                    score += 10
                    feedback.append(f'{pname}={actual_f:.0f} ✓ (+10)')
                else:
                    feedback.append(f'{pname}={actual_f:.0f} (need {req_val}) (+0)')
            except (ValueError, TypeError):
                feedback.append(f'{pname} value invalid (+0)')
        else:
            feedback.append(f'{pname} not read from vehicle (+0)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }