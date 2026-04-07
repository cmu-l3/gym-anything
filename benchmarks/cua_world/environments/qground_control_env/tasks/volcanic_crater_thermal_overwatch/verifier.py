#!/usr/bin/env python3
"""Verifier for volcanic_crater_thermal_overwatch task.

Evaluates 3 distinct software UI domains: Application Settings, Parameters, and Plan View.

Scoring (100 pts total, pass = 75):
  15  Video RTSP URL configured correctly
  15  RTL_ALT parameter set to 15000 (150m) via pymavlink
  10  Mission file created/modified during task
  15  Takeoff AND Waypoint command present
  20  ROI (Region of Interest) command (201) present
  15  Loiter Time command (19) present with duration = 1800s
  10  RTL command (20) present at the end
"""

import json
import os
import tempfile

TARGET_RTSP = "rtsp://192.168.144.25:8554/thermal"
TARGET_RTL_ALT = 15000.0

CMD_NAV_WAYPOINT = 16
CMD_NAV_LOITER_TIME = 19
CMD_NAV_RETURN_TO_LAUNCH = 20
CMD_NAV_TAKEOFF = 22
CMD_DO_SET_ROI_LOCATION = 201


def verify_volcanic_crater_overwatch(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Read exported result
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

    # --- 1. Check RTSP Config (15 pts) ---
    actual_rtsp = str(result.get('rtsp_url', '')).strip()
    details['rtsp_url'] = actual_rtsp
    if actual_rtsp == TARGET_RTSP:
        score += 15
        feedback.append('RTSP video stream configured correctly (+15)')
    elif "192.168.144.25" in actual_rtsp:
        score += 5
        feedback.append(f'RTSP stream partially correct: {actual_rtsp} (+5)')
    else:
        feedback.append('RTSP video stream NOT configured correctly (+0)')

    # --- 2. Check RTL_ALT Parameter (15 pts) ---
    params = result.get('params', {})
    actual_rtl_alt = params.get('RTL_ALT')
    details['RTL_ALT'] = actual_rtl_alt
    if actual_rtl_alt is not None:
        try:
            val = float(actual_rtl_alt)
            if abs(val - TARGET_RTL_ALT) <= 100:  # Allow 1m tolerance
                score += 15
                feedback.append(f'RTL_ALT set to {val:.0f} ✓ (+15)')
            else:
                feedback.append(f'RTL_ALT is {val:.0f} (needed 15000) (+0)')
        except ValueError:
            feedback.append('RTL_ALT returned invalid value (+0)')
    else:
        feedback.append('RTL_ALT parameter could not be read (+0)')

    # --- 3. Check File Modified (10 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    if file_found and modified:
        score += 10
        feedback.append('Plan file exists and was modified during task (+10)')
    elif file_found:
        feedback.append('Plan file exists but was NOT modified during task (+0)')
    else:
        feedback.append('Plan file NOT found (+0)')
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    # --- Parse Mission Plan ---
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
    commands = [it.get('command') for it in items]
    
    # --- 4. Takeoff & Waypoint (15 pts) ---
    has_takeoff = CMD_NAV_TAKEOFF in commands
    has_wp = CMD_NAV_WAYPOINT in commands
    if has_takeoff and has_wp:
        score += 15
        feedback.append('Takeoff & Navigation Waypoints found (+15)')
    elif has_wp:
        score += 10
        feedback.append('Navigation Waypoint found, but Takeoff missing (+10)')
    else:
        feedback.append('Missing Waypoint navigation commands (+0)')

    # --- 5. ROI Command (20 pts) ---
    if CMD_DO_SET_ROI_LOCATION in commands:
        score += 20
        feedback.append('DO_SET_ROI_LOCATION command found (+20)')
    else:
        feedback.append('ROI command missing (+0)')

    # --- 6. Loiter Time Command (15 pts) ---
    loiter_items = [it for it in items if it.get('command') == CMD_NAV_LOITER_TIME]
    if loiter_items:
        # Check if the time is 1800s. QGC stores time in param 1 (params array index 0)
        time_correct = False
        for it in loiter_items:
            params_arr = it.get('params', [])
            if len(params_arr) > 0 and params_arr[0] is not None:
                try:
                    loiter_time = float(params_arr[0])
                    if abs(loiter_time - 1800) < 5:
                        time_correct = True
                        break
                except ValueError:
                    pass
        
        if time_correct:
            score += 15
            feedback.append('Loiter Time command (1800s) found (+15)')
        else:
            score += 5
            feedback.append('Loiter Time command found but duration != 1800s (+5)')
    else:
        feedback.append('Loiter Time command missing (+0)')

    # --- 7. RTL Command (10 pts) ---
    if CMD_NAV_RETURN_TO_LAUNCH in commands:
        score += 10
        feedback.append('Return To Launch command found (+10)')
    else:
        feedback.append('Return To Launch command missing (+0)')

    passed = score >= 75

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }