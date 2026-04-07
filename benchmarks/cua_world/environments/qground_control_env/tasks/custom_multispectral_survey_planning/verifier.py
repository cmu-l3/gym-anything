#!/usr/bin/env python3
"""Verifier for custom_multispectral_survey_planning task.

Checks that the agent created a QGC survey mission plan that uses a
Custom Camera configuration perfectly matching the provided specs.

Scoring (100 pts total, pass = 75):
  10  File exists and was modified during task
  10  Mission Structure (Takeoff + Survey + RTL)
  15  Sensor Width (13.2 ±0.1)
  15  Sensor Height (8.8 ±0.1)
  15  Focal Length (12.0 ±0.1)
   7.5 Image Width (5472)
   7.5 Image Height (3648)
  10  Altitude (120 ±1)
   5  Frontal Overlap (80 ±1)
   5  Side Overlap (75 ±1)
"""

import json
import os
import tempfile


def _find_values(obj, target_key):
    """Recursively find all values for a given key (case-insensitive) in a nested dict/list."""
    results = []
    target_lower = target_key.lower()
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.lower() == target_lower:
                results.append(v)
            if isinstance(v, (dict, list)):
                results.extend(_find_values(v, target_key))
    elif isinstance(obj, list):
        for item in obj:
            results.extend(_find_values(item, target_key))
    return results


def _find_survey_items(plan):
    """Find all survey complex items in a QGC plan."""
    surveys = []
    mission = plan.get('mission', {})
    items = mission.get('items', [])
    for item in items:
        if item.get('complexItemType') == 'survey' or item.get('type') == 'ComplexItem':
            surveys.append(item)
        # Check for nested TransectStyleComplexItem
        if item.get('TransectStyleComplexItem', {}):
            surveys.append(item)
    return surveys


def check_float(actual, expected, tolerance=0.1):
    try:
        return abs(float(actual) - float(expected)) <= tolerance
    except (TypeError, ValueError):
        return False


def verify_custom_multispectral_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Expected values
    exp_sw = metadata.get('sensor_width_mm', 13.2)
    exp_sh = metadata.get('sensor_height_mm', 8.8)
    exp_fl = metadata.get('focal_length_mm', 12.0)
    exp_iw = metadata.get('image_width_px', 5472)
    exp_ih = metadata.get('image_height_px', 3648)
    exp_alt = metadata.get('target_altitude_m', 120)
    exp_fo = metadata.get('frontal_overlap_pct', 80)
    exp_so = metadata.get('side_overlap_pct', 75)
    f_tol = metadata.get('float_tolerance', 0.1)
    i_tol = metadata.get('int_tolerance', 1)

    # Get the export result
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

    # --- Check 1: File Status (10 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    if file_found and modified:
        score += 10
        feedback.append('Plan file exists and was modified (+10)')
    elif file_found:
        feedback.append('Plan file exists but was NOT modified during task (+0)')
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Parse the plan file ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 2: Mission Structure (10 pts) ---
    items = plan.get('mission', {}).get('items', [])
    has_takeoff = any(i.get('command') == 22 for i in items)
    has_rtl = any(i.get('command') == 20 for i in items)
    survey_items = _find_survey_items(plan)
    has_survey = len(survey_items) > 0

    struct_pts = 0
    if has_takeoff: struct_pts += 3
    if has_survey: struct_pts += 4
    if has_rtl: struct_pts += 3
    
    score += struct_pts
    feedback.append(f'Mission structure points: {struct_pts}/10 (Takeoff:{has_takeoff}, Survey:{has_survey}, RTL:{has_rtl})')

    if not has_survey:
        feedback.append('No survey item found. Cannot verify camera parameters.')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    survey_item = survey_items[0]

    # Helper to check a specific value within the survey item
    def score_metric(key, expected, tolerance, pts, name):
        nonlocal score
        found_vals = _find_values(survey_item, key)
        if not found_vals:
            feedback.append(f'{name} ({key}) missing (+0/{pts})')
            return
        
        # Consider it correct if ANY match (sometimes QGC leaves stale data in other keys, but CameraCalc is what matters)
        for val in found_vals:
            if check_float(val, expected, tolerance):
                score += pts
                feedback.append(f'{name} correct: {val} ✓ (+{pts})')
                details[key] = val
                return
        
        # If we get here, no match found
        actual = found_vals[0]
        feedback.append(f'{name} incorrect: found {actual}, expected {expected} (+0/{pts})')
        details[key] = actual

    # --- Check 3: Sensor Dimensions (30 pts) ---
    score_metric('sensorWidth', exp_sw, f_tol, 15, 'Sensor Width')
    score_metric('sensorHeight', exp_sh, f_tol, 15, 'Sensor Height')

    # --- Check 4: Focal Length (15 pts) ---
    score_metric('focalLength', exp_fl, f_tol, 15, 'Focal Length')

    # --- Check 5: Image Resolution (15 pts) ---
    score_metric('imageWidth', exp_iw, f_tol, 7.5, 'Image Width')
    score_metric('imageHeight', exp_ih, f_tol, 7.5, 'Image Height')

    # --- Check 6: Flight Altitude (10 pts) ---
    # distanceToSurface might be nested in CameraCalc or at top level of survey
    # _find_values searches everything inside the survey block
    score_metric('distanceToSurface', exp_alt, i_tol, 10, 'Altitude')

    # --- Check 7: Overlap Configuration (10 pts) ---
    score_metric('frontalOverlap', exp_fo, i_tol, 5, 'Frontal Overlap')
    score_metric('sideOverlap', exp_so, i_tol, 5, 'Side Overlap')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }