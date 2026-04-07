#!/usr/bin/env python3
"""Verifier for tactical_throw_deployment_setup task.

Checks that the agent:
1. Configured 6 critical ArduPilot parameters for a tactical drop deployment.
2. Created a sign-off report confirming the configuration.

Required Values:
  FLTMODE1        = 18   (Throw Mode)
  THROW_TYPE      = 1    (Downward drop)
  THROW_NEXTMODE  = 5    (Loiter)
  THROW_MOT_START = 1    (Start immediately on drop detection)
  MOT_SPIN_ARM    = 0.0  (Propellers stationary while armed in hand)
  DISARM_DELAY    = 0    (Disable auto-disarming)

Scoring (100 pts total, pass = 75):
  15 pts per parameter (6 params * 15 = 90)
  10 pts for valid sign-off report created during task containing required phrase
"""

import json
import os
import tempfile

REQUIRED_PARAMS = {
    'FLTMODE1':        (18.0, 15, 0.4),
    'THROW_TYPE':      (1.0,  15, 0.4),
    'THROW_NEXTMODE':  (5.0,  15, 0.4),
    'THROW_MOT_START': (1.0,  15, 0.4),
    'MOT_SPIN_ARM':    (0.0,  15, 0.05),
    'DISARM_DELAY':    (0.0,  15, 0.4)
}

REQUIRED_PHRASE = "throw mode configured"


def verify_tactical_throw_deployment_setup(traj, env_info, task_info):
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

    if not result.get('connected', True) and all(params.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 'score': 0,
            'feedback': 'SITL not reachable during export — no parameters could be read'
        }

    # --- Parameter checks (90 pts) ---
    for param_name, (required_val, pts, tol) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual
        
        if actual is not None:
            try:
                actual_f = float(actual)
                if abs(actual_f - required_val) <= tol:
                    score += pts
                    if int(required_val) == required_val:
                        feedback.append(f'{param_name}={int(actual_f)} ✓ (+{pts})')
                    else:
                        feedback.append(f'{param_name}={actual_f:.2f} ✓ (+{pts})')
                else:
                    feedback.append(f'{param_name}={actual_f} (need {required_val}) (+0/{pts})')
            except (TypeError, ValueError):
                feedback.append(f'{param_name}=invalid (+0/{pts})')
        else:
            feedback.append(f'{param_name}: not read (+0/{pts})')

    # --- Report file checks (10 pts) ---
    report_found = result.get('report_found', False)
    report_modified = result.get('report_modified', False)
    
    if report_found and report_modified:
        report_content = result.get('report_content', '')
        if isinstance(report_content, str):
            report_content = report_content.replace('\\n', '\n').replace('\\t', '\t')
            
        if REQUIRED_PHRASE.lower() in report_content.lower():
            score += 10
            feedback.append('Sign-off report complete and contains required phrase (+10)')
            details['report_valid'] = True
        else:
            feedback.append(f'Sign-off report missing required phrase: "{REQUIRED_PHRASE}" (+0/10)')
            details['report_valid'] = False
    elif report_found:
        feedback.append('Report file exists but was not modified/created during the task (+0/10)')
        details['report_valid'] = False
    else:
        feedback.append('Sign-off report not found (+0/10)')
        details['report_valid'] = False

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }