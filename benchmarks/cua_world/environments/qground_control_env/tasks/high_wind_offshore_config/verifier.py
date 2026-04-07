#!/usr/bin/env python3
"""Verifier for high_wind_offshore_config task.

Checks that the agent:
1. Translates physical units to ArduPilot native parameters and applies them.
2. Extracts the SYSID_THISMAV vehicle ID.
3. Generates a sign-off report containing the required data.

Required parameters & tolerances:
  ANGLE_MAX     = 4500 (±10)    [from 45 degrees]
  WPNAV_SPEED   = 1200 (±10)    [from 12 m/s]
  WPNAV_ACCEL   = 250  (±5)     [from 2.5 m/s^2]
  RTL_SPEED     = 1500 (±10)    [from 15 m/s]
  RTL_ALT       = 500  (±10)    [from 5 m]
  FS_EKF_THRESH = 1.0  (±0.05)  [from 1.0]

Scoring (100 pts total, pass = 70):
  10 pts each for the 6 parameters (60 points total)
  15 pts for report existing and having content
  15 pts for correctly identifying SYSID_THISMAV (default 1) in the report
  10 pts for correctly writing the key tuning values (45 and 15) in the report
"""

import json
import os
import re
import tempfile

REQUIRED_PARAMS = {
    'ANGLE_MAX':     (4500.0, 10, 10.0),
    'WPNAV_SPEED':   (1200.0, 10, 10.0),
    'WPNAV_ACCEL':   (250.0,  10, 5.0),
    'RTL_SPEED':     (1500.0, 10, 10.0),
    'RTL_ALT':       (500.0,  10, 10.0),
    'FS_EKF_THRESH': (1.0,    10, 0.05),
}

def verify_high_wind_offshore_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    expected_sysid = metadata.get('expected_sysid', 1)

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

    if not params.get('connected', True):
        feedback.append("WARNING: Could not fetch live parameters from SITL.")

    # --- Verify the 6 Drone Parameters (60 pts) ---
    for param_name, (required_val, pts, tol) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                actual_f = float(actual)
                if abs(actual_f - required_val) <= tol:
                    score += pts
                    feedback.append(f'{param_name}={actual_f:.1f} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual_f:.1f} (need {required_val:.1f} ±{tol}) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')

    # --- Verify Report File (40 pts) ---
    report_found = result.get('report_found', False)
    report_modified = result.get('report_modified', False)
    report_size = result.get('report_size', 0)
    
    details['report_found'] = report_found
    details['report_modified'] = report_modified
    details['report_size'] = report_size

    # Report existence & size (15 pts)
    if report_found and report_modified and report_size > 20:
        score += 15
        feedback.append(f'Report file created and valid size ({report_size} bytes) (+15)')
    elif report_found and report_size > 20:
        score += 7
        feedback.append(f'Report file exists but was not modified during the task (+7/15)')
    else:
        feedback.append('Report file missing or empty (+0/15)')

    if report_found:
        report_content = result.get('report_content', '')
        if isinstance(report_content, str):
            report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
        
        # SYSID check (15 pts)
        # Looking for "System ID: 1" or just a prominent "1" associated with SYSID
        sysid_pattern = re.compile(rf'\b(?:SYSID|System\s*ID|ID).*?\b({expected_sysid})\b', re.IGNORECASE)
        if sysid_pattern.search(report_content):
            score += 15
            feedback.append(f'Vehicle System ID ({expected_sysid}) correctly reported (+15)')
            details['sysid_reported'] = True
        else:
            feedback.append(f'Vehicle System ID ({expected_sysid}) not found in report (+0/15)')
            details['sysid_reported'] = False

        # Physical Values check (10 pts)
        # Checking if 45 (angle) and 15 (speed) are documented
        has_45 = bool(re.search(r'\b45\b', report_content))
        has_15 = bool(re.search(r'\b15\b', report_content))
        
        if has_45 and has_15:
            score += 10
            feedback.append('Max Angle (45) and RTL Speed (15) documented in report (+10)')
            details['values_reported'] = True
        elif has_45 or has_15:
            score += 5
            feedback.append('Partial tuning values documented in report (+5/10)')
            details['values_reported'] = 'partial'
        else:
            feedback.append('Tuning values not documented in report (+0/10)')
            details['values_reported'] = False

    passed = score >= 70

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }