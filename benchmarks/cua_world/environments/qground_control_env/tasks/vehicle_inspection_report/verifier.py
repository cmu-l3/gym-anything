#!/usr/bin/env python3
"""Verifier for vehicle_inspection_report task.

Checks flight mode parameters, ATC gains, and inspection report content.

Required flight modes:
  FLTMODE1=2 (AltHold), FLTMODE2=5 (Loiter), FLTMODE3=3 (Auto),
  FLTMODE4=6 (RTL), FLTMODE5=9 (Land), FLTMODE6=16 (PosHold)

Required ATC gains (within ±0.2 of 4.0):
  ATC_ANG_RLL_P in [3.8, 4.2]
  ATC_ANG_PIT_P in [3.8, 4.2]

Scoring (100 pts total, pass = 75):
  10  FLTMODE1 == 2
  10  FLTMODE2 == 5
  10  FLTMODE3 == 3
   8  FLTMODE4 == 6
   8  FLTMODE5 == 9
   7  FLTMODE6 == 16
   8  ATC_ANG_RLL_P in [3.8, 4.2]
   8  ATC_ANG_PIT_P in [3.8, 4.2]
  15  Report exists and was modified during task
   4  Report size > 200 bytes
   7  Mode names in report (at least 3 of: AltHold, Loiter, Auto, RTL, Land, PosHold)
   5  GPS coordinates (lat/lon pattern) in report
"""

import json
import os
import re
import tempfile

REQUIRED_FLTMODES = {
    'FLTMODE1': (2.0,  10),
    'FLTMODE2': (5.0,  10),
    'FLTMODE3': (3.0,  10),
    'FLTMODE4': (6.0,   8),
    'FLTMODE5': (9.0,   8),
    'FLTMODE6': (16.0,  7),
}
MODE_NAMES = ['althold', 'loiter', 'auto', 'rtl', 'land', 'poshold']

GPS_PATTERN = re.compile(
    r'(?:lat(?:itude)?|lon(?:gitude)?|gps|position).*?'
    r'(\d{1,3}\.?\d{0,8})',
    re.IGNORECASE | re.DOTALL
)

COORD_PATTERN = re.compile(
    r'\b4[0-9]\.\d{2,}\b.*?\b[0-9]\.\d{2,}\b|\b[0-9]\.\d{2,}\b.*?\b4[0-9]\.\d{2,}\b',
    re.DOTALL
)


def verify_vehicle_inspection_report(traj, env_info, task_info):
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

    # --- Flight mode checks ---
    for param_name, (required_val, pts) in REQUIRED_FLTMODES.items():
        actual = params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                if abs(float(actual) - required_val) < 0.5:
                    score += pts
                    feedback.append(f'{param_name}={int(actual)} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual} (need {required_val:.0f}) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')

    # --- ATC gain checks ---
    for param_name, pts in [('ATC_ANG_RLL_P', 8), ('ATC_ANG_PIT_P', 8)]:
        actual = params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                actual_f = float(actual)
                if 3.8 <= actual_f <= 4.2:
                    score += pts
                    feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual_f:.2f} (need 3.8-4.2) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')

    # --- Report file checks ---
    report_found = result.get('report_found', False)
    report_modified = result.get('report_modified', False)
    report_size = result.get('report_size', 0)
    details['report_found'] = report_found
    details['report_modified'] = report_modified
    details['report_size'] = report_size

    # Exists + modified (15 pts combined)
    if report_found and report_modified:
        score += 15
        feedback.append('Inspection report created during task (+15)')
    elif report_found:
        score += 7
        feedback.append('Report exists but not modified during task (+7)')
    else:
        feedback.append('Inspection report not found (+0/15)')

    # Size > 200 bytes (4 pts)
    if report_found and report_size > 200:
        score += 4
        feedback.append(f'Report has content ({report_size} bytes) (+4)')
    elif report_found:
        feedback.append(f'Report too small ({report_size} bytes, need >200) (+0/4)')

    # Content checks
    if report_found:
        report_content = result.get('report_content', '')
        if isinstance(report_content, str):
            report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
        report_lower = report_content.lower()

        # Mode names check (7 pts): at least 3 mode names present
        modes_found = sum(1 for m in MODE_NAMES if m in report_lower)
        details['mode_names_found'] = modes_found
        if modes_found >= 4:
            score += 7
            feedback.append(f'Mode names in report ({modes_found}/6) (+7)')
        elif modes_found >= 2:
            score += 3
            feedback.append(f'Some mode names in report ({modes_found}/6) (+3 partial)')
        else:
            feedback.append(f'Mode names not found in report ({modes_found}/6) (+0/7)')

        # GPS coordinates (5 pts): look for coordinate-like numbers near Zurich
        # Zurich lat ~47.39, lon ~8.54 — look for patterns like "47." or "8.54"
        has_lat = bool(re.search(r'\b47\.\d', report_content))
        has_lon = bool(re.search(r'\b8\.\d', report_content))
        # Also accept any decimal coordinate pairs
        has_coords = has_lat or has_lon or bool(COORD_PATTERN.search(report_content))
        details['has_gps_coords'] = has_coords
        if has_coords:
            score += 5
            feedback.append('GPS coordinates found in report (+5)')
        else:
            feedback.append('GPS coordinates not found in report (+0/5)')
    else:
        feedback.append('Report content checks skipped (file not found)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }
