#!/usr/bin/env python3
"""Verifier for slung_payload_mag_survey task.

Checks that the agent correctly configured both mission planning properties and 
live vehicle parameters for a slung payload.

Scoring (100 pts total, pass = 75):
  10  File exists & was created during task
  15  Survey ComplexItem present in plan
  15  Survey Turnaround Distance is approx 30m
   5  Survey Altitude is approx 40m
  15  Delay Command (60s) present in plan
  12  WPNAV_SPEED set to 300
  14  WPNAV_ACCEL set to 100
  14  ANGLE_MAX set to 2000
"""

import json
import os
import tempfile

def _find_values(obj, key):
    """Recursively find all values for a given key in a nested dict/list."""
    results = []
    if isinstance(obj, dict):
        if key in obj:
            results.append(obj[key])
        for v in obj.values():
            results.extend(_find_values(v, key))
    elif isinstance(obj, list):
        for item in obj:
            results.extend(_find_values(item, key))
    return results

def verify_slung_payload_mag_survey(traj, env_info, task_info):
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

    # --- CRITERION 1: File Exists & Modified (10 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    
    if file_found and modified:
        score += 10
        feedback.append('Plan file created successfully (+10)')
    elif file_found:
        score += 5
        feedback.append('Plan file exists but might not be newly created (+5)')
    else:
        feedback.append('Plan file not found (+0)')

    # --- PLAN CONTENT VERIFICATION ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    
    plan = {}
    if plan_content_raw:
        try:
            plan = json.loads(plan_content_raw)
        except Exception as e:
            feedback.append(f'Could not parse plan JSON: {e}')

    mission_items = plan.get('mission', {}).get('items', [])
    
    # --- CRITERION 2: Survey Item Present (15 pts) ---
    all_complex_types = _find_values(plan, 'complexItemType')
    has_survey = 'survey' in [str(t).lower() for t in all_complex_types]
    
    if has_survey:
        score += 15
        feedback.append('Survey pattern found (+15)')
    else:
        feedback.append('No Survey pattern found in plan (+0)')

    # --- CRITERION 3 & 4: Turnaround Distance (15 pts) & Altitude (5 pts) ---
    if has_survey:
        turnarounds = _find_values(plan, 'turnAroundDistance')
        turnaround_ok = any(28 <= float(t) <= 32 for t in turnarounds if t is not None)
        
        if turnaround_ok:
            score += 15
            feedback.append('Turnaround distance configured to ~30m ✓ (+15)')
        elif turnarounds:
            feedback.append(f'Turnaround distance incorrect (found {turnarounds}) (+0/15)')
        else:
            feedback.append('Could not find turnaround distance parameter (+0/15)')
            
        altitudes = _find_values(plan, 'distanceToSurface') + _find_values(plan, 'Altitude')
        alt_ok = any(38 <= float(a) <= 42 for a in altitudes if a is not None)
        
        if alt_ok:
            score += 5
            feedback.append('Survey altitude configured to ~40m ✓ (+5)')
        elif altitudes:
            feedback.append(f'Survey altitude incorrect (found {altitudes[:3]}...) (+0/5)')
    else:
        feedback.append('Cannot verify Survey properties (no survey found) (+0/20)')

    # --- CRITERION 5: Delay Command Present (15 pts) ---
    # NAV_DELAY is command 93. Parameter 1 is the delay in seconds.
    delay_found = False
    for item in mission_items:
        if item.get('command') == 93:
            params = item.get('params', [])
            # Usually the delay time is in params[0] or 'param1'
            if len(params) > 0 and params[0] is not None:
                delay_val = float(params[0])
                if 58 <= delay_val <= 62:
                    delay_found = True
                    break

    if delay_found:
        score += 15
        feedback.append('60s Delay command found ✓ (+15)')
    else:
        feedback.append('60s Delay command not found (+0/15)')

    # --- PARAMETERS VERIFICATION ---
    params_data = result.get('params', {})
    
    # WPNAV_SPEED (12 pts)
    wpnav_speed = params_data.get('WPNAV_SPEED')
    if wpnav_speed is not None and 295 <= float(wpnav_speed) <= 305:
        score += 12
        feedback.append('WPNAV_SPEED=300 ✓ (+12)')
    else:
        feedback.append(f'WPNAV_SPEED={wpnav_speed} (need 300) (+0/12)')

    # WPNAV_ACCEL (14 pts)
    wpnav_accel = params_data.get('WPNAV_ACCEL')
    if wpnav_accel is not None and 95 <= float(wpnav_accel) <= 105:
        score += 14
        feedback.append('WPNAV_ACCEL=100 ✓ (+14)')
    else:
        feedback.append(f'WPNAV_ACCEL={wpnav_accel} (need 100) (+0/14)')

    # ANGLE_MAX (14 pts)
    angle_max = params_data.get('ANGLE_MAX')
    if angle_max is not None and 1990 <= float(angle_max) <= 2010:
        score += 14
        feedback.append('ANGLE_MAX=2000 ✓ (+14)')
    else:
        feedback.append(f'ANGLE_MAX={angle_max} (need 2000) (+0/14)')

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }