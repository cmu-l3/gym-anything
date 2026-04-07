#!/usr/bin/env python3
"""Verifier for telemetry_stream_config task.

Checks stream rate parameters and the generated report.

Required parameters:
  SR0_RAW_SENS = 1
  SR0_EXT_STAT = 1
  SR0_RC_CHAN  = 0
  SR0_RAW_CTRL = 0
  SR0_POSITION = 3
  SR0_EXTRA1   = 4
  SR0_EXTRA2   = 1
  SR0_EXTRA3   = 1

Scoring (100 pts total, pass = 65):
  10  SR0_RAW_SENS == 1
  10  SR0_EXT_STAT == 1
  10  SR0_RC_CHAN == 0
  10  SR0_RAW_CTRL == 0
  12  SR0_POSITION == 3
  12  SR0_EXTRA1 == 4
  10  SR0_EXTRA2 == 1
  10  SR0_EXTRA3 == 1
  10  Report exists and was modified during task
   6  Report > 200 bytes and contains at least 4 parameter names
"""

import json
import os
import tempfile

REQUIRED_PARAMS = {
    'SR0_RAW_SENS': (1.0, 10),
    'SR0_EXT_STAT': (1.0, 10),
    'SR0_RC_CHAN':  (0.0, 10),
    'SR0_RAW_CTRL': (0.0, 10),
    'SR0_POSITION': (3.0, 12),
    'SR0_EXTRA1':   (4.0, 12),
    'SR0_EXTRA2':   (1.0, 10),
    'SR0_EXTRA3':   (1.0, 10),
}


def verify_telemetry_stream_config(traj, env_info, task_info):
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
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read',
            'details': details
        }

    # --- Parameter checks ---
    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual
        if actual is not None:
            try:
                actual_f = float(actual)
                if abs(actual_f - required_val) <= 0.4:
                    score += pts
                    feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0/{pts})')
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

    # Exists + modified (10 pts)
    if report_found and report_modified:
        score += 10
        feedback.append('Summary report created during task (+10)')
    elif report_found:
        score += 5
        feedback.append('Report exists but not modified during task (+5)')
    else:
        feedback.append('Summary report not found (+0/10)')

    # Size > 200 bytes & content analysis (6 pts)
    if report_found and report_size > 200:
        report_content = result.get('report_content', '')
        if isinstance(report_content, str):
            report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
            
        matches = 0
        for p in REQUIRED_PARAMS.keys():
            if p.lower() in report_content.lower():
                matches += 1
                
        details['report_param_mentions'] = matches
        
        if matches >= 4:
            score += 6
            feedback.append(f'Report has detailed content ({report_size} bytes, {matches} params mentioned) (+6)')
        else:
            feedback.append(f'Report has content but missing parameters ({matches} params mentioned) (+0/6)')
    elif report_found:
        feedback.append(f'Report too small ({report_size} bytes, need >200) (+0/6)')

    passed = score >= 65
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }