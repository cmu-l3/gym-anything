#!/usr/bin/env python3
"""Verifier for water_quality_sampling_mission task.

Checks:
- RTL_ALT == 2000
- WPNAV_SPEED_DN == 50
- Mission plan exists and modified
- Target coordinates ~ 47.3970, 8.5450
- Low altitude descent (<= 3.0m)
- Relay ON command (cmd 181, param2=1)
- Loiter Time (cmd 19, param1 >= 45)
- Relay OFF command (cmd 181, param2=0)
- RTL command (cmd 20)

Total: 100 pts. Pass threshold: 75
"""

import json
import os
import tempfile

def _get_param(item, index, default=None):
    """Extract a parameter from a QGC SimpleItem."""
    params = item.get('params', [])
    if isinstance(params, list) and len(params) > index and params[index] is not None:
        return params[index]
    return default

def verify_water_quality_sampling_mission(traj, env_info, task_info):
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

    # --- Parameter checks (20 pts) ---
    params = result.get('params', {})
    rtl_alt = params.get('RTL_ALT')
    wpnav_speed_dn = params.get('WPNAV_SPEED_DN')
    
    if rtl_alt is not None and abs(float(rtl_alt) - 2000.0) <= 10.0:
        score += 10
        feedback.append('RTL_ALT=2000 ✓ (+10)')
    else:
        feedback.append(f'RTL_ALT={rtl_alt} (need 2000) (+0)')
        
    if wpnav_speed_dn is not None and abs(float(wpnav_speed_dn) - 50.0) <= 5.0:
        score += 10
        feedback.append('WPNAV_SPEED_DN=50 ✓ (+10)')
    else:
        feedback.append(f'WPNAV_SPEED_DN={wpnav_speed_dn} (need 50) (+0)')

    # --- File checks (10 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    
    if file_found and modified:
        score += 10
        feedback.append('Mission plan created (+10)')
    else:
        feedback.append('Mission plan not found or not created during task (+0)')
        # Fast exit if no plan
        if not file_found:
            return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

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
    
    target_coords_found = False
    low_alt_found = False
    relay_on_found = False
    relay_off_found = False
    loiter_found = False
    rtl_found = False

    for item in items:
        cmd = item.get('command')
        
        # Check coords
        if cmd in [16, 17, 19, 21, 31]:  # NAV commands
            lat = _get_param(item, 4)
            lon = _get_param(item, 5)
            if lat is not None and lon is not None:
                if abs(float(lat) - 47.3970) <= 0.002 and abs(float(lon) - 8.5450) <= 0.002:
                    target_coords_found = True
                    
        # Check low alt (<= 3.0 m)
        # Check in params[6]
        alt = _get_param(item, 6)
        if alt is not None and 0.0 <= float(alt) <= 3.0:
            low_alt_found = True
        # Check explicit Altitude key
        alt_key = item.get('Altitude')
        if alt_key is not None and 0.0 <= float(alt_key) <= 3.0:
            low_alt_found = True

        # Check relay commands
        if cmd == 181:  # MAV_CMD_DO_SET_RELAY
            # param2 is the setting (0=off, 1=on)
            setting = _get_param(item, 1)
            if setting is not None:
                if abs(float(setting) - 1.0) < 0.1:
                    relay_on_found = True
                elif abs(float(setting) - 0.0) < 0.1:
                    relay_off_found = True

        # Check loiter time
        if cmd == 19:  # MAV_CMD_NAV_LOITER_TIME
            # param1 is time in seconds
            loiter_time = _get_param(item, 0)
            if loiter_time is not None and float(loiter_time) >= 44.0:
                loiter_found = True

        # Check RTL
        if cmd == 20:  # MAV_CMD_NAV_RETURN_TO_LAUNCH
            rtl_found = True

    # --- Mission structure checks (70 pts) ---
    if target_coords_found:
        score += 10
        feedback.append('Target coords (47.3970, 8.5450) found ✓ (+10)')
    else:
        feedback.append('Target coords not found (+0)')
        
    if low_alt_found:
        score += 10
        feedback.append('Low altitude descent (<= 3.0m) found ✓ (+10)')
    else:
        feedback.append('Low altitude descent not found (+0)')
        
    if relay_on_found:
        score += 15
        feedback.append('Relay ON command found ✓ (+15)')
    else:
        feedback.append('Relay ON command not found (+0)')
        
    if loiter_found:
        score += 10
        feedback.append('Loiter time >= 45s found ✓ (+10)')
    else:
        feedback.append('Loiter time (>=45s) not found (+0)')
        
    if relay_off_found:
        score += 15
        feedback.append('Relay OFF command found ✓ (+15)')
    else:
        feedback.append('Relay OFF command not found (+0)')
        
    if rtl_found:
        score += 10
        feedback.append('RTL command found ✓ (+10)')
    else:
        feedback.append('RTL command not found (+0)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }