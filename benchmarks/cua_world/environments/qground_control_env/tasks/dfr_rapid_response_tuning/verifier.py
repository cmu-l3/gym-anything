#!/usr/bin/env python3
"""Verifier for dfr_rapid_response_tuning task.

Evaluates if the agent successfully converted m/s to cm/s based on the QGC UI 
and set the parameters correctly, and produced the commissioning report.

Scoring (100 pts total, pass threshold 75):
  12 pts  WPNAV_SPEED == 2200    (Spec asked for 22.0 m/s)
  12 pts  WPNAV_SPEED_UP == 600  (Spec asked for 6.0 m/s)
  12 pts  WPNAV_SPEED_DN == 400  (Spec asked for 4.0 m/s)
  12 pts  WPNAV_ACCEL == 350     (Spec asked for 3.5 m/s/s)
  12 pts  WPNAV_RADIUS == 800    (Spec asked for 8.0 m)
  12 pts  LAND_SPEED == 80       (Spec asked for 0.8 m/s)
  15 pts  Report exists and was modified during task
  13 pts  Report contains the speed (e.g. "22" or "2200")
"""

import json
import os
import tempfile
import re

REQUIRED_PARAMS = {
    'WPNAV_SPEED':    (2200.0, 12, 22.0),
    'WPNAV_SPEED_UP': (600.0,  12, 6.0),
    'WPNAV_SPEED_DN': (400.0,  12, 4.0),
    'WPNAV_ACCEL':    (350.0,  12, 3.5),
    'WPNAV_RADIUS':   (800.0,  12, 8.0),
    'LAND_SPEED':     (80.0,   12, 0.8),
}

TOLERANCE = 2.0


def verify_dfr_tuning(traj, env_info, task_info):
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

    # 1. Parameter Checks (72 pts total)
    for param_name, (expected_converted_val, pts, raw_unconverted_val) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual
        
        if actual is None:
            feedback.append(f'{param_name}: not read (+0)')
            continue
            
        try:
            actual_f = float(actual)
            
            # Agent successfully converted
            if abs(actual_f - expected_converted_val) <= TOLERANCE:
                score += pts
                feedback.append(f'{param_name}={actual_f:.0f} ✓ (Converted correctly) (+{pts})')
            # Agent failed to convert (copy-pasted raw value)
            elif abs(actual_f - raw_unconverted_val) <= TOLERANCE:
                feedback.append(f'{param_name}={actual_f:.1f} ❌ (Failed to convert units to cm/s) (+0)')
            # Completely wrong
            else:
                feedback.append(f'{param_name}={actual_f:.1f} (need {expected_converted_val:.0f}) (+0)')
        except (TypeError, ValueError):
            feedback.append(f'{param_name}=invalid (+0)')

    # 2. Report Existence Check (15 pts)
    report_found = result.get('report_found', False)
    report_modified = result.get('report_modified', False)
    details['report_found'] = report_found
    details['report_modified'] = report_modified
    
    if report_found and report_modified:
        score += 15
        feedback.append('Commissioning report created/modified during task (+15)')
    elif report_found:
        score += 5
        feedback.append('Report exists but not modified during task (+5 partial)')
    else:
        feedback.append('Commissioning report not found (+0)')

    # 3. Report Content Check (13 pts)
    if report_found:
        report_content = result.get('report_content', '')
        if isinstance(report_content, str):
            report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
            
        report_lower = report_content.lower()
        
        # Check if the speed 22 or 2200 is mentioned as requested in the instructions
        if re.search(r'\b(22|22\.0|2200)\b', report_lower):
            score += 13
            feedback.append('Report mentions the configured speed correctly (+13)')
        else:
            feedback.append('Report does not clearly state the 22 m/s transit speed (+0)')
            
    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }