#!/usr/bin/env python3
"""Verifier for maritime_shipboard_follow_config task.

Checks parameter subsystem configuration via MAVLink and geometric details 
of the saved Rally Point file.

Scoring (100 pts total, pass = 75):
Parameters (65 points):
  10  FOLL_ENABLE = 1
  10  FOLL_SYSID = 112
  15  FOLL_OFS_X = -60
  10  FOLL_OFS_Z = 45
  10  FOLL_YAW_BEHAV = 2
   5  FLTMODE6 = 17
   5  FS_GCS_ENABLE = 0
   
File Outputs (35 points):
  10  Rally Point file created/modified
  15  First Rally Point Coordinates Lat/Lon
  10  First Rally Point Altitude
"""

import json
import os
import tempfile

def verify_maritime_follow_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    result_file = '/tmp/task_result.json'

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

    # 1. Parameter Checks (65 points total)
    params = result.get('params', {})
    
    if params.get('FOLL_ENABLE') is not None and abs(float(params['FOLL_ENABLE']) - 1.0) < 0.1:
        score += 10
        feedback.append('FOLL_ENABLE=1 ✓ (+10)')
    else:
        feedback.append(f"FOLL_ENABLE={params.get('FOLL_ENABLE')} (need 1) (+0/10)")

    if params.get('FOLL_SYSID') is not None and abs(float(params['FOLL_SYSID']) - 112.0) < 0.1:
        score += 10
        feedback.append('FOLL_SYSID=112 ✓ (+10)')
    else:
        feedback.append(f"FOLL_SYSID={params.get('FOLL_SYSID')} (need 112) (+0/10)")

    if params.get('FOLL_OFS_X') is not None and -61.0 <= float(params['FOLL_OFS_X']) <= -59.0:
        score += 15
        feedback.append(f"FOLL_OFS_X={params.get('FOLL_OFS_X')} ✓ (+15)")
    else:
        feedback.append(f"FOLL_OFS_X={params.get('FOLL_OFS_X')} (need -60) (+0/15)")

    if params.get('FOLL_OFS_Z') is not None and 44.0 <= float(params['FOLL_OFS_Z']) <= 46.0:
        score += 10
        feedback.append(f"FOLL_OFS_Z={params.get('FOLL_OFS_Z')} ✓ (+10)")
    else:
        feedback.append(f"FOLL_OFS_Z={params.get('FOLL_OFS_Z')} (need 45) (+0/10)")

    if params.get('FOLL_YAW_BEHAV') is not None and abs(float(params['FOLL_YAW_BEHAV']) - 2.0) < 0.1:
        score += 10
        feedback.append('FOLL_YAW_BEHAV=2 ✓ (+10)')
    else:
        feedback.append(f"FOLL_YAW_BEHAV={params.get('FOLL_YAW_BEHAV')} (need 2) (+0/10)")

    if params.get('FLTMODE6') is not None and abs(float(params['FLTMODE6']) - 17.0) < 0.1:
        score += 5
        feedback.append('FLTMODE6=17 ✓ (+5)')
    else:
        feedback.append(f"FLTMODE6={params.get('FLTMODE6')} (need 17) (+0/5)")

    if params.get('FS_GCS_ENABLE') is not None and abs(float(params['FS_GCS_ENABLE']) - 0.0) < 0.1:
        score += 5
        feedback.append('FS_GCS_ENABLE=0 ✓ (+5)')
    else:
        feedback.append(f"FS_GCS_ENABLE={params.get('FS_GCS_ENABLE')} (need 0) (+0/5)")

    # 2. File Checks (35 points total)
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    
    if file_found and modified:
        score += 10
        feedback.append('Rally Point file created/modified ✓ (+10)')
        
        plan_content = result.get('plan_content', '{}')
        if isinstance(plan_content, str):
            plan_content = plan_content.replace('\\n', '\n').replace('\\t', '\t')
        
        try:
            plan = json.loads(plan_content)
            rally_pts = plan.get('rallyPoints', {}).get('points', [])
            
            if len(rally_pts) > 0:
                pt = rally_pts[0]
                lat = pt[0] if len(pt) > 0 else 0
                lon = pt[1] if len(pt) > 1 else 0
                alt = pt[2] if len(pt) > 2 else 0
                
                # Check coordinates (Lat: -35.3655, Lon: 149.1610)
                if abs(lat - (-35.3655)) <= 0.0005 and abs(lon - 149.1610) <= 0.0005:
                    score += 15
                    feedback.append(f'Rally Point coords correct ({lat}, {lon}) ✓ (+15)')
                else:
                    feedback.append(f'Rally Point coords incorrect ({lat}, {lon}) (+0/15)')
                    
                # Check altitude (15m)
                if abs(alt - 15.0) <= 0.5:
                    score += 10
                    feedback.append(f'Rally Point alt correct ({alt}) ✓ (+10)')
                else:
                    feedback.append(f'Rally Point alt incorrect ({alt}) (+0/10)')
            else:
                feedback.append('No Rally Points found in file (+0/25)')
        except Exception as e:
            feedback.append(f'Failed to parse Rally Point file: {e} (+0/25)')
    else:
        feedback.append('Rally Point file missing or not modified (+0/35)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback)
    }