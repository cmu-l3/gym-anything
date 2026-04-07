#!/usr/bin/env python3
"""Verifier for bvlos_smart_rtl_failsafe_config task.

Checks:
1. 5 required ArduPilot Smart RTL / Failsafe parameters.
2. Saved mission plan file existence and modifications.
3. Rally Points placed at the exact requested coordinates in the plan.

Scoring (100 pts total, pass = 70):
  10 pts: FS_GCS_ENABLE == 3
  10 pts: BATT_FS_LOW_ACT == 3
  10 pts: FS_THR_ENABLE == 4
  10 pts: SRTL_POINTS == 500
  10 pts: SRTL_ACCURACY == 1
  10 pts: Plan file exists and created/modified during task
  20 pts: Rally Point Alpha found at Lat 47.3980, Lon 8.5450 (±0.0005)
  20 pts: Rally Point Bravo found at Lat 47.3990, Lon 8.5470 (±0.0005)
"""

import json
import os
import math
import tempfile

# Parameters configuration
REQUIRED_PARAMS = {
    'FS_GCS_ENABLE': (3.0, 10),
    'BATT_FS_LOW_ACT': (3.0, 10),
    'FS_THR_ENABLE': (4.0, 10),
    'SRTL_POINTS': (500.0, 10),
    'SRTL_ACCURACY': (1.0, 10),
}

# Coordinate checking
TOLERANCE_DEG = 0.0005
TARGET_RALLY_PTS = [
    (47.3980, 8.5450, 20, "Alpha LZ"),
    (47.3990, 8.5470, 20, "Bravo LZ")
]

def calculate_distance(lat1, lon1, lat2, lon2):
    """Simple euclidean distance for small variations."""
    return math.sqrt((lat1 - lat2)**2 + (lon1 - lon2)**2)

def verify_bvlos_smart_rtl_failsafe_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Retrieve exported JSON result
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
    
    # Check 1: Parameters Evaluation (Total: 50 pts)
    params = result.get('params', {})
    if not params.get('connected', True):
        feedback.append("SITL connection failed, unable to verify parameters (+0/50)")
    else:
        for p_name, (expected_val, pts) in REQUIRED_PARAMS.items():
            actual = params.get(p_name)
            details[p_name] = actual
            if actual is not None:
                try:
                    if abs(float(actual) - expected_val) < 0.5:
                        score += pts
                        feedback.append(f'{p_name}={int(actual)} ✓ (+{pts})')
                    else:
                        feedback.append(f'{p_name}={actual} (need {expected_val}) (+0/{pts})')
                except (TypeError, ValueError):
                    feedback.append(f'{p_name}=invalid (+0/{pts})')
            else:
                feedback.append(f'{p_name} not found (+0/{pts})')

    # Check 2: File Creation/Modification (Total: 10 pts)
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    details['file_found'] = file_found
    details['modified_during_task'] = modified
    
    if file_found and modified:
        score += 10
        feedback.append("Plan file created/modified correctly (+10)")
    elif file_found:
        feedback.append("Plan file exists but was NOT modified during task (+0/10)")
    else:
        feedback.append("Plan file not found at expected path (+0/10)")
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # Check 3: Rally Points Validation (Total: 40 pts)
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f"Cannot parse plan JSON: {e} (+0/40)")
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}
        
    rally_section = plan.get('rallyPoints', {})
    rally_pts = rally_section.get('points', [])
    details['found_rally_points'] = rally_pts
    
    # We copy target list to track which ones have been matched
    unmatched_targets = list(TARGET_RALLY_PTS)
    
    for r_pt in rally_pts:
        if not isinstance(r_pt, list) or len(r_pt) < 2:
            continue
            
        r_lat, r_lon = float(r_pt[0]), float(r_pt[1])
        matched_target = None
        
        for t_idx, t in enumerate(unmatched_targets):
            t_lat, t_lon, pts, label = t
            dist = calculate_distance(r_lat, r_lon, t_lat, t_lon)
            if dist <= TOLERANCE_DEG:
                score += pts
                feedback.append(f"Rally Point {label} found ✓ (+{pts})")
                matched_target = t_idx
                break
                
        if matched_target is not None:
            unmatched_targets.pop(matched_target)

    # Any left over didn't get found
    for t in unmatched_targets:
        feedback.append(f"Missing Rally Point {t[3]} (+0/{t[2]})")

    # Final scoring check
    passed = score >= 70
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }