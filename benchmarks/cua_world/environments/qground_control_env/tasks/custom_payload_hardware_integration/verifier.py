#!/usr/bin/env python3
"""Verifier for custom_payload_hardware_integration task.

Checks whether the 8 specified parameters were configured correctly,
and whether the correct completion string was logged to the file.

Since some parameters (like MNT1_PITCH_MIN) might be processed by QGroundControl
in degrees vs centidegrees depending on backend version, the verifier handles
both explicit and scaled inputs (e.g., -60 vs -6000) for robustness.

Scoring (100 points total, Pass Threshold = 80):
  10 pts: MNT1_TYPE == 1
  10 pts: CAM1_TYPE == 1
  10 pts: SERVO9_FUNCTION == 7
  10 pts: SERVO10_FUNCTION == 8
  10 pts: SERVO11_FUNCTION == 10
  10 pts: MNT1_PITCH_MIN == -60 (or -6000)
  10 pts: MNT1_PITCH_MAX == 15 (or 1500)
  10 pts: CAM1_DURATION == 5 (or 50)
  20 pts: Log file created containing "INTEGRATION COMPLETE: GIMBAL AND CAMERA"
"""

import json
import os
import tempfile

def check_param(actual_val, expected_options, tolerance=0.5):
    """Check if actual_val is within tolerance of any expected_options."""
    if actual_val is None:
        return False
    try:
        val = float(actual_val)
        for expected in expected_options:
            if abs(val - expected) <= tolerance:
                return True
        return False
    except (TypeError, ValueError):
        return False

def verify_custom_payload_hardware_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    expected_phrase = metadata.get('expected_phrase', 'INTEGRATION COMPLETE: GIMBAL AND CAMERA').upper()

    # Retrieve export result JSON
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

    # Disconnected SITL handling
    if not params.get('connected', True):
        feedback.append("SITL disconnected during verification; cannot read parameters.")
    
    # 1. Parameter Checks (80 points total)
    param_checks = [
        ('MNT1_TYPE', [1], 10),
        ('CAM1_TYPE', [1], 10),
        ('SERVO9_FUNCTION', [7], 10),
        ('SERVO10_FUNCTION', [8], 10),
        ('SERVO11_FUNCTION', [10], 10),
        # Accept explicit or scaled values for degrees/centidegrees scaling
        ('MNT1_PITCH_MIN', [-60, -6000], 10),
        ('MNT1_PITCH_MAX', [15, 1500], 10),
        ('CAM1_DURATION', [5, 50], 10)
    ]

    for param_name, valid_options, pts in param_checks:
        actual = params.get(param_name)
        details[param_name] = actual
        
        # Scale tolerance for very large numbers just in case
        tol = 0.5 if abs(valid_options[0]) < 100 else 5.0
        
        if check_param(actual, valid_options, tol):
            score += pts
            feedback.append(f'{param_name}={actual} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual} (need {valid_options[0]}) (+0/{pts})')

    # 2. Log File Checks (20 points total)
    log_found = result.get('log_found', False)
    log_modified = result.get('log_modified', False)
    log_content = result.get('log_content', '')
    
    if isinstance(log_content, str):
        log_content = log_content.replace('\\n', '\n').replace('\\t', '\t').strip().upper()

    details['log_found'] = log_found
    details['log_modified'] = log_modified

    if log_found and log_modified:
        if expected_phrase in log_content:
            score += 20
            feedback.append('Integration log created with correct completion phrase ✓ (+20)')
        else:
            feedback.append('Integration log found, but missing exact completion phrase (+0/20)')
            details['log_content_mismatch'] = True
    elif log_found:
        feedback.append('Integration log found, but not modified during task (+0/20)')
    else:
        feedback.append('Integration log not found (+0/20)')

    passed = score >= 80

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }