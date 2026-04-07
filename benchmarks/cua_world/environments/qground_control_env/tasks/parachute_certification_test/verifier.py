#!/usr/bin/env python3
"""Verifier for parachute_certification_test task.

Checks parameters and mission file parsing.

Parameters (10 pts each):
  CHUTE_ENABLED == 1
  CHUTE_TYPE == 10
  SERVO9_FUNCTION == 27
  CHUTE_ALT_MIN == 25

Mission File:
  File exists & modified during task (5 pts)
  Takeoff command (CMD 22) at ~80m (10 pts)
  Waypoint command (CMD 16) at Lat ~-35.3615, Lon ~149.1650, Alt ~80m (15 pts)
  DO_PARACHUTE command (CMD 208) with param1=2 for release (30 pts)

Scoring (100 pts total, Pass = 80).
Requires doing the majority of both parameter and mission config successfully.
"""

import json
import os
import tempfile


# MAVLink Command Constants
MAV_CMD_NAV_WAYPOINT = 16
MAV_CMD_NAV_TAKEOFF = 22
MAV_CMD_DO_PARACHUTE = 208

# Expected Parameter Configuration
REQUIRED_PARAMS = {
    'CHUTE_ENABLED': (1.0, 10),
    'CHUTE_TYPE': (10.0, 10),
    'SERVO9_FUNCTION': (27.0, 10),
    'CHUTE_ALT_MIN': (25.0, 10),
}


def _get_item_altitude(item):
    """Extract altitude from a SimpleItem, trying Altitude field and params[6]."""
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


def verify_parachute_certification(traj, env_info, task_info):
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
    params = result.get('params', {})

    # --- 1. Parameter Checks (40 pts) ---
    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                if abs(float(actual) - required_val) < 0.5:
                    score += pts
                    feedback.append(f'{param_name}={int(actual)} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual} (need {int(required_val)}) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')

    # --- 2. Mission File Basic Checks (5 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    if file_found and modified:
        score += 5
        feedback.append('Plan file exists and was modified (+5)')
    elif file_found:
        feedback.append('Plan file exists but was not modified during task (+0)')
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- 3. Parse Plan Content ---
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

    # --- 4. Mission Sequence Checks ---
    has_takeoff = False
    has_waypoint = False
    has_parachute = False

    for item in items:
        cmd = item.get('command')
        
        # Takeoff Check (10 pts)
        if cmd == MAV_CMD_NAV_TAKEOFF and not has_takeoff:
            alt = _get_item_altitude(item)
            if alt is not None and abs(alt - 80) <= 5:
                score += 10
                feedback.append(f'Takeoff command at ~80m ({alt}m) found (+10)')
                has_takeoff = True
            elif alt is not None:
                feedback.append(f'Takeoff found, but altitude is {alt}m (need ~80m) (+0)')

        # Waypoint Check (15 pts)
        elif cmd == MAV_CMD_NAV_WAYPOINT and not has_waypoint:
            alt = _get_item_altitude(item)
            # Try to get lat/lon from params[4] and params[5]
            p = item.get('params', [])
            if len(p) >= 7:
                lat, lon = p[4], p[5]
                try:
                    lat, lon = float(lat), float(lon)
                    lat_ok = abs(lat - (-35.3615)) < 0.005
                    lon_ok = abs(lon - 149.1650) < 0.005
                    alt_ok = alt is not None and abs(alt - 80) <= 5
                    
                    if lat_ok and lon_ok and alt_ok:
                        score += 15
                        feedback.append('Drop Zone Waypoint correctly configured (+15)')
                        has_waypoint = True
                    elif lat_ok and lon_ok:
                        feedback.append(f'Drop Zone Waypoint found, but altitude is {alt}m (need ~80m) (+0)')
                except (TypeError, ValueError):
                    pass
        
        # Parachute Check (30 pts)
        elif cmd == MAV_CMD_DO_PARACHUTE and not has_parachute:
            p = item.get('params', [])
            if len(p) > 0:
                try:
                    action = float(p[0])
                    if abs(action - 2.0) < 0.1:  # 2 is Release/Trigger
                        score += 30
                        feedback.append('DO_PARACHUTE command set to Release (+30)')
                        has_parachute = True
                    else:
                        feedback.append(f'DO_PARACHUTE command found, but Action is {action} (need 2 for Release) (+0)')
                except (TypeError, ValueError):
                    pass

    if not has_takeoff and sum(1 for i in items if i.get('command') == MAV_CMD_NAV_TAKEOFF) == 0:
        feedback.append('Takeoff command missing (+0)')
    if not has_waypoint and sum(1 for i in items if i.get('command') == MAV_CMD_NAV_WAYPOINT) == 0:
        feedback.append('Drop Zone Waypoint missing/incorrect (+0)')
    if not has_parachute and sum(1 for i in items if i.get('command') == MAV_CMD_DO_PARACHUTE) == 0:
        feedback.append('DO_PARACHUTE command missing (+0)')

    # Final scoring
    passed = score >= 80
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }