#!/usr/bin/env python3
"""Verifier for swarm_drone_show_commissioning task.

Checks:
1. Exported .params file exists and contains the parameters
2. Sign-off report exists and contains required keywords
3. Live parameters on the flight controller match the required values

Scoring (100 pts total, pass = 75):
  10  Exported .params file is valid
  10  Sign-off report is valid
  80  (10 per param) Live parameter matches AND is present correctly in export file
"""

import json
import os
import tempfile

def check_param_in_file(content, param_name, expected_val):
    if not content:
        return False
        
    for line in content.split('\n'):
        line = line.strip()
        if line.startswith('#') or not line:
            continue
            
        # QGC uses space or tab separated columns
        parts = line.split()
        if len(parts) >= 4 and parts[2] == param_name:
            try:
                val = float(parts[3])
                if abs(val - expected_val) < 0.1:
                    return True
            except ValueError:
                pass
                
        # Also handle potential CSV just in case
        parts_csv = line.split(',')
        if len(parts_csv) >= 4 and parts_csv[2] == param_name:
            try:
                val = float(parts_csv[3])
                if abs(val - expected_val) < 0.1:
                    return True
            except ValueError:
                pass
                
    return False

def verify_swarm_commissioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {})

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
    
    params_file_exists = result.get('params_file_exists', False)
    report_exists = result.get('report_exists', False)
    params_content = result.get('params_content', '')
    report_content = result.get('report_content', '')
    live_params = result.get('live_params', {})
    
    details['params_file_exists'] = params_file_exists
    details['report_exists'] = report_exists
    
    # 1. Check Params file (10 pts)
    if params_file_exists and "SYSID_THISMAV" in params_content:
        score += 10
        feedback.append("Parameter export file exists and contains parameters (+10)")
    else:
        feedback.append("Parameter export file missing or invalid (+0)")
        
    # 2. Check Signoff report (10 pts)
    if isinstance(report_content, str):
        report_content = report_content.replace('\\n', '\n')
    
    if report_exists and len(report_content) > 30 and "42" in report_content and "land" in report_content.lower():
        score += 10
        feedback.append("Sign-off report exists and contains required keywords (+10)")
    elif report_exists:
        feedback.append("Sign-off report exists but lacks required content/keywords (+0)")
    else:
        feedback.append("Sign-off report missing (+0)")
        
    # 3. Check parameters (10 pts each)
    if not live_params.get('connected', True) and all(live_params.get(p) is None for p in required_params):
        feedback.append("WARNING: SITL not reachable during export, could not read live parameters.")
        
    for param_name, required_val in required_params.items():
        live_val = live_params.get(param_name)
        details[param_name] = live_val
        
        in_file = check_param_in_file(params_content, param_name, required_val)
        
        if live_val is not None:
            try:
                actual_f = float(live_val)
                if abs(actual_f - required_val) < 0.1:
                    if params_file_exists:
                        if in_file:
                            score += 10
                            feedback.append(f"{param_name}={actual_f:.0f} matches live AND in export (+10)")
                        else:
                            score += 5
                            feedback.append(f"{param_name}={actual_f:.0f} matches live BUT incorrect/missing in export (+5)")
                    else:
                        score += 8
                        feedback.append(f"{param_name}={actual_f:.0f} matches live (no export file) (+8)")
                else:
                    feedback.append(f"{param_name}={actual_f:.0f} (need {required_val:.0f}) (+0)")
            except (TypeError, ValueError):
                feedback.append(f"{param_name}=invalid (+0)")
        else:
            feedback.append(f"{param_name}: not read (+0)")

    passed = score >= 75
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }