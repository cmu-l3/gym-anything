#!/usr/bin/env python3
"""Verifier for cargo_winch_delivery_config task.

Checks:
1. Parameters: WINCH_RATE_MAX=2.5, SERVO9_FUNCTION=46, RC8_OPTION=45
2. Mission plan existence and timestamps.
3. Mission sequence:
   - Takeoff (cmd 22)
   - Waypoint (cmd 16)
   - DO_WINCH lower (cmd 42600, action=1, len=15, rate=1)
   - NAV_DELAY (cmd 93, delay=20)
   - DO_WINCH retract (cmd 42600, action=1, len=0, rate=2.5)
   - RTL (cmd 20)

Scoring (100 pts total, pass = 75):
  10  WINCH_RATE_MAX = 2.5
  10  SERVO9_FUNCTION = 46
  10  RC8_OPTION = 45
  10  Plan file exists and was modified
   5  Takeoff command
   5  Waypoint command
  20  DO_WINCH (Lower) configured correctly
  15  NAV_DELAY configured correctly
  10  DO_WINCH (Retract) configured correctly
   5  RTL command
"""

import json
import os
import tempfile

def _get_param(item, index, default=0.0):
    """Safely extract a float value from a MAVLink command param array."""
    params = item.get('params', [])
    if index < len(params) and params[index] is not None:
        try:
            return float(params[index])
        except (TypeError, ValueError):
            pass
    return default

def verify_cargo_winch_delivery_config(traj, env_info, task_info):
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

    # --- Check 1: Parameters (30 pts) ---
    params = result.get('params', {})
    
    req_params = {
        'WINCH_RATE_MAX': (2.5, 10, 0.1),
        'SERVO9_FUNCTION': (46.0, 10, 0.1),
        'RC8_OPTION': (45.0, 10, 0.1)
    }

    for pname, (pval, pts, tol) in req_params.items():
        actual = params.get(pname)
        details[pname] = actual
        if actual is not None:
            try:
                if abs(float(actual) - pval) <= tol:
                    score += pts
                    feedback.append(f'{pname}={actual} ✓ (+{pts})')
                else:
                    feedback.append(f'{pname}={actual} (need {pval}) (+0)')
            except (ValueError, TypeError):
                feedback.append(f'{pname}=invalid (+0)')
        else:
            feedback.append(f'{pname} not set/read (+0)')

    # --- Check 2: File Existence & MTime (10 pts) ---
    file_found = result.get('file_found', False)
    file_modified = result.get('modified_during_task', False)
    
    if file_found and file_modified:
        score += 10
        feedback.append('Mission plan saved correctly (+10)')
    elif file_found:
        score += 5
        feedback.append('Mission plan found but not modified during task (+5)')
    else:
        feedback.append('Mission plan not found (+0)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 3: Parse Mission Plan ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    commands = [it.get('command') for it in items]
    
    # 3.1: Takeoff (5 pts)
    if 22 in commands:
        score += 5
        feedback.append('Takeoff command found (+5)')
    else:
        feedback.append('Takeoff command missing (+0)')

    # 3.2: Waypoint (5 pts)
    if 16 in commands:
        score += 5
        feedback.append('Waypoint command found (+5)')
    else:
        feedback.append('Waypoint command missing (+0)')

    # 3.3: DO_WINCH operations and NAV_DELAY
    winch_cmds = [it for it in items if it.get('command') == 42600]
    delay_cmds = [it for it in items if it.get('command') == 93]

    # Lower winch: Action=1, Length=15, Rate=1
    lower_winch_found = False
    for wc in winch_cmds:
        action = _get_param(wc, 1)  # Param 2 (Action)
        length = _get_param(wc, 2)  # Param 3 (Release Length)
        rate = _get_param(wc, 3)    # Param 4 (Rate)
        if abs(action - 1.0) < 0.1 and abs(length - 15.0) < 0.5 and abs(rate - 1.0) < 0.1:
            lower_winch_found = True
            break
            
    if lower_winch_found:
        score += 20
        feedback.append('DO_WINCH (Lower) configured correctly (+20)')
    elif len(winch_cmds) > 0:
        feedback.append('DO_WINCH found, but parameters for lowering are incorrect (+0)')
    else:
        feedback.append('DO_WINCH (Lower) missing (+0)')

    # Delay: Param 1 = 20
    delay_found = False
    for dc in delay_cmds:
        delay_val = _get_param(dc, 0) # Param 1
        if abs(delay_val - 20.0) < 0.5:
            delay_found = True
            break
            
    if delay_found:
        score += 15
        feedback.append('NAV_DELAY configured correctly (+15)')
    elif len(delay_cmds) > 0:
        feedback.append('NAV_DELAY found, but duration is not 20s (+0)')
    else:
        feedback.append('NAV_DELAY missing (+0)')

    # Retract winch: Action=1, Length=0, Rate=2.5
    retract_winch_found = False
    for wc in winch_cmds:
        action = _get_param(wc, 1)  # Param 2 (Action)
        length = _get_param(wc, 2)  # Param 3 (Release Length)
        rate = _get_param(wc, 3)    # Param 4 (Rate)
        if abs(action - 1.0) < 0.1 and abs(length - 0.0) < 0.5 and abs(rate - 2.5) < 0.1:
            retract_winch_found = True
            break
            
    if retract_winch_found:
        score += 10
        feedback.append('DO_WINCH (Retract) configured correctly (+10)')
    elif len(winch_cmds) > 0 and not lower_winch_found:
        feedback.append('DO_WINCH (Retract) missing or incorrect (+0)')

    # 3.4: RTL (5 pts)
    if 20 in commands:
        score += 5
        feedback.append('RTL command found (+5)')
    else:
        feedback.append('RTL command missing (+0)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }