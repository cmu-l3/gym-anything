#!/usr/bin/env python3
"""Verifier for vibration_notch_filter_tuning task.

Checks Harmonic Notch Filter parameters and the summary text file.

Required parameters:
  INS_HNTCH_ENABLE = 1
  INS_HNTCH_MODE   = 1
  INS_HNTCH_FREQ   = 92
  INS_HNTCH_BW     = 46
  INS_HNTCH_REF    = 0.24
  INS_HNTCH_ATT    = 40
  INS_LOG_BAT_OPT  = 2

Required file content elements in filter_summary.txt:
  - "92" (Freq)
  - "46" (Bandwidth)
  - "0.24" (Reference thrust)
  - "Ready for post-filter test flight" (Exact phrase)

Scoring (100 pts total, pass = 75):
  10  INS_HNTCH_ENABLE = 1
  10  INS_HNTCH_MODE = 1
  15  INS_HNTCH_FREQ = 92
  15  INS_HNTCH_BW = 46
  15  INS_HNTCH_REF = 0.24
  10  INS_HNTCH_ATT = 40
  10  INS_LOG_BAT_OPT = 2
   5  Summary file exists and modified during task
   3  Frequency "92" present in file
   3  Bandwidth "46" present in file
   4  Thrust "0.24" present in file
  (The phrase is checked for strict compliance but points are distributed above)
"""

import json
import os
import tempfile

REQUIRED_PARAMS = {
    'INS_HNTCH_ENABLE': (1.0, 10),
    'INS_HNTCH_MODE':   (1.0, 10),
    'INS_HNTCH_FREQ':   (92.0, 15),
    'INS_HNTCH_BW':     (46.0, 15),
    'INS_HNTCH_REF':    (0.24, 15),
    'INS_HNTCH_ATT':    (40.0, 10),
    'INS_LOG_BAT_OPT':  (2.0, 10),
}

TOLERANCES = {
    'INS_HNTCH_ENABLE': 0.1,
    'INS_HNTCH_MODE':   0.1,
    'INS_HNTCH_FREQ':   1.0,
    'INS_HNTCH_BW':     1.0,
    'INS_HNTCH_REF':    0.02,
    'INS_HNTCH_ATT':    1.0,
    'INS_LOG_BAT_OPT':  0.1,
}

REQUIRED_PHRASE = "ready for post-filter test flight"

def verify_vibration_notch_filter_tuning(traj, env_info, task_info):
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

    if not result.get('params', {}).get('connected', True) and all(result.get('params', {}).get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read'
        }

    score = 0
    feedback = []
    details = {}
    params = result.get('params', {})

    # --- Parameter checks ---
    for param_name, (required_val, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback.append(f'{param_name}: not read (+0/{pts})')
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback.append(f'{param_name}: invalid value {actual} (+0/{pts})')
            continue

        tol = TOLERANCES.get(param_name, 0.1)
        if abs(actual_f - required_val) <= tol:
            score += pts
            if param_name in ['INS_HNTCH_FREQ', 'INS_HNTCH_BW', 'INS_HNTCH_ATT', 'INS_LOG_BAT_OPT']:
                feedback.append(f'{param_name}={actual_f:.0f} ✓ (+{pts})')
            else:
                feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{pts})')
        else:
            feedback.append(f'{param_name}={actual_f} (need {required_val}) (+0/{pts})')

    # --- File checks ---
    summary_found = result.get('summary_found', False)
    summary_modified = result.get('summary_modified', False)
    
    if summary_found and summary_modified:
        score += 5
        feedback.append('Summary file created/modified during task (+5)')
        
        content = result.get('summary_content', '')
        if isinstance(content, str):
            content = content.replace('\\n', '\n').replace('\\t', '\t')
        
        content_lower = content.lower()
        
        if "92" in content:
            score += 3
            feedback.append('Frequency "92" found in summary (+3)')
        else:
            feedback.append('Frequency "92" missing from summary (+0/3)')
            
        if "46" in content:
            score += 3
            feedback.append('Bandwidth "46" found in summary (+3)')
        else:
            feedback.append('Bandwidth "46" missing from summary (+0/3)')
            
        if "0.24" in content:
            score += 4
            feedback.append('Reference Thrust "0.24" found in summary (+4)')
        else:
            feedback.append('Reference Thrust "0.24" missing from summary (+0/4)')
            
        if REQUIRED_PHRASE in content_lower:
            feedback.append('Confirmation phrase found in summary ✓')
        else:
            feedback.append('Confirmation phrase missing or incorrect spelling.')
            
    elif summary_found:
        feedback.append('Summary file found but not modified during task (+0/15)')
    else:
        feedback.append('Summary file not found (+0/15)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }