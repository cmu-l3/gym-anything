#!/usr/bin/env python3
"""Verifier for satcom_telemetry_bandwidth_reduction task.

Checks that the agent:
1. Configured the live SR2_* parameters on the vehicle correctly (56 pts).
2. Exported the parameters to the correct file path (satcom_link.params) (10 pts).
3. Exported the file during the task execution (10 pts).
4. Ensured the exported file is a valid QGC param file containing the correct values (24 pts).

Scoring (100 pts total, pass = 75):
  Live Parameters (56 pts):
    7 pts each for the 8 SR2_* parameters matching the target (0 or 1).
  
  File Export (44 pts):
    10 pts if satcom_link.params exists.
    10 pts if modified/created during the task.
    24 pts if the file contains the 8 target SR2_* parameters correctly formatted (3 pts each).
"""

import json
import os
import tempfile

# Target parameter values specified in the brief
TARGET_PARAMS = {
    'SR2_POSITION': 1.0,
    'SR2_EXT_STAT': 1.0,
    'SR2_EXTRA1': 1.0,
    'SR2_EXTRA2': 1.0,
    'SR2_EXTRA3': 0.0,
    'SR2_RAW_CTRL': 0.0,
    'SR2_RAW_SENS': 0.0,
    'SR2_RC_CHAN': 0.0
}


def parse_qgc_param_file(content):
    """
    Parses a QGroundControl .params file.
    Expected format: 
    # Comments...
    SYSID COMPID PARAM_NAME VALUE TYPE
    """
    params = {}
    lines = content.splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        
        parts = line.split()
        # Ensure it has at least SYSID, COMPID, PARAM_NAME, VALUE
        if len(parts) >= 4:
            param_name = parts[2]
            try:
                param_value = float(parts[3])
                params[param_name] = param_value
            except ValueError:
                pass
                
    return params


def verify_satcom_telemetry_bandwidth_reduction(traj, env_info, task_info):
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

    # --- Part 1: Live Parameters Verification (56 pts) ---
    live_params = result.get('live_params', {})
    if not live_params.get('connected', True) and all(live_params.get(p) is None for p in TARGET_PARAMS):
        feedback.append('WARNING: SITL not reachable during export — no live parameters could be read.')
    
    live_score = 0
    for param_name, target_val in TARGET_PARAMS.items():
        actual = live_params.get(param_name)
        details[f'live_{param_name}'] = actual

        if actual is not None:
            try:
                if abs(float(actual) - target_val) < 0.1:
                    live_score += 7
                    feedback.append(f'Live {param_name}={int(actual)} ✓ (+7)')
                else:
                    feedback.append(f'Live {param_name}={actual} (need {target_val:.0f}) (+0)')
            except (TypeError, ValueError):
                feedback.append(f'Live {param_name} is invalid (+0)')
        else:
            feedback.append(f'Live {param_name} could not be read (+0)')
            
    score += live_score

    # --- Part 2: File Export Verification (44 pts) ---
    file_found = result.get('file_found', False)
    file_modified = result.get('file_modified', False)
    file_content_raw = result.get('file_content', '')
    
    details['file_found'] = file_found
    details['file_modified'] = file_modified

    if file_found:
        score += 10
        feedback.append('Export file satcom_link.params found (+10)')
        
        if file_modified:
            score += 10
            feedback.append('Export file was created/modified during task (+10)')
        else:
            feedback.append('Export file existed before task began (+0)')
            
        # Parse file content
        if isinstance(file_content_raw, str):
            file_content_raw = file_content_raw.replace('\\n', '\n').replace('\\t', '\t')
            
        file_params = parse_qgc_param_file(file_content_raw)
        details['parsed_file_params'] = file_params
        
        file_param_score = 0
        for param_name, target_val in TARGET_PARAMS.items():
            if param_name in file_params:
                if abs(file_params[param_name] - target_val) < 0.1:
                    file_param_score += 3
                    feedback.append(f'File {param_name}={int(file_params[param_name])} ✓ (+3)')
                else:
                    feedback.append(f'File {param_name} has incorrect value {file_params[param_name]} (+0)')
            else:
                feedback.append(f'File missing {param_name} (+0)')
        
        score += file_param_score

    else:
        feedback.append('Export file satcom_link.params NOT found. Did you save it? (+0/44 for file checks)')

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }