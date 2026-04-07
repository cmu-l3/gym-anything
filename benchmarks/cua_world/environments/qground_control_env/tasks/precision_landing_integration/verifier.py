#!/usr/bin/env python3
"""Verifier for precision_landing_integration task.

Checks live ArduPilot parameters via pymavlink and validates the creation
of a parameter backup file.

Required Live Parameters (70 points total):
  PLND_ENABLED   = 1    (10 pts)
  PLND_TYPE      = 2    (10 pts)
  RNGFND1_TYPE   = 20   (10 pts)
  RNGFND1_MAX_CM = 1500 (10 pts)
  RNGFND1_MIN_CM = 20   (10 pts)
  RNGFND1_ORIENT = 25   (10 pts)
  LAND_SPEED     = 10   (10 pts)

Backup File Validation (30 points total):
  File exists and modified during task (15 pts)
  File size > 10KB and contains 'PLND_ENABLED' string (15 pts)

Scoring (100 pts total, pass = 80):
  The high pass threshold forces the agent to both configure live parameters
  AND successfully navigate the QGC menu to export the backup file.
"""

import json
import os
import tempfile

REQUIRED_PARAMS = {
    'PLND_ENABLED':   (1.0, 10),
    'PLND_TYPE':      (2.0, 10),
    'RNGFND1_TYPE':   (20.0, 10),
    'RNGFND1_MAX_CM': (1500.0, 10),
    'RNGFND1_MIN_CM': (20.0, 10),
    'RNGFND1_ORIENT': (25.0, 10),
    'LAND_SPEED':     (10.0, 10),
}

def verify_precision_landing_integration(traj, env_info, task_info):
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

    if not params.get('connected', True) and all(params.get(p) is None for p in REQUIRED_PARAMS):
        feedback.append("WARNING: SITL not reachable during export. No live parameters could be read.")
    
    # --- Live Parameter Checks ---
    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                actual_f = float(actual)
                # Tolerance of 0.5 is sufficient since all required values are integers
                if abs(actual_f - required_val) < 0.5:
                    score += pts
                    feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')

    # --- Backup File Checks ---
    backup_found = result.get('backup_found', False)
    backup_modified = result.get('modified_during_task', False)
    backup_size = result.get('backup_size', 0)
    contains_plnd = result.get('contains_plnd', False)
    
    details['backup_found'] = backup_found
    details['backup_modified'] = backup_modified
    details['backup_size'] = backup_size
    details['contains_plnd'] = contains_plnd

    # Exists + modified (15 pts)
    if backup_found and backup_modified:
        score += 15
        feedback.append('Parameter backup file created during task (+15)')
    elif backup_found:
        score += 5
        feedback.append('Backup file exists but was not modified during task (+5/15)')
    else:
        feedback.append('Parameter backup file not found (+0/15)')

    # Size + validity (15 pts)
    # A full ArduPilot parameter dump from QGC is typically 30KB - 60KB.
    # 5KB is a very safe minimum to ensure it's a real dump and not an empty file.
    if backup_found and backup_size > 5000 and contains_plnd:
        score += 15
        feedback.append(f'Backup file is valid and contains configuration ({backup_size // 1024} KB) (+15)')
    elif backup_found and backup_size > 0:
        feedback.append(f'Backup file exists but does not appear to be a complete valid param dump ({backup_size} bytes) (+0/15)')

    passed = score >= 80
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }