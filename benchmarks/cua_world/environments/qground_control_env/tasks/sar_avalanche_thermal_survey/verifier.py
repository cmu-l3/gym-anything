#!/usr/bin/env python3
"""Verifier for sar_avalanche_thermal_survey task.

Checks:
1. File exists and modified (10 points)
2. Survey polygon valid (>=3 vertices) (10 points)
3. Custom Camera dimensions (640x512) (15 points)
4. Custom Camera optics (sensor size 10.88x8.16, focal length 13.0) (15 points)
5. Survey Altitude = 80m (10 points)
6. Survey Overlaps (Frontal 80, Side 70) (10 points)
7. WEATH_ENABLE == 1 (15 points)
8. RTL_SPEED == 1500 (15 points)

Total: 100 points, Pass threshold: 75 points.
"""

import json
import os
import tempfile

def _find_survey_items(plan):
    """Find all survey complex items in a QGC plan."""
    surveys = []
    mission = plan.get('mission', {})
    items = mission.get('items', [])
    for item in items:
        # Check standard complexItemType
        if item.get('complexItemType') == 'survey':
            surveys.append(item)
        # Older / different formatting where it's wrapped
        elif item.get('type') == 'ComplexItem' and 'TransectStyleComplexItem' in item:
            surveys.append(item)
    return surveys

def _count_polygon_vertices(polygon):
    """Count vertices in a QGC polygon (path or polygon key)."""
    path = polygon.get('path', polygon.get('polygon', polygon.get('vertices', [])))
    if isinstance(path, list):
        return len(path)
    return 0

def _get_nested_val(data, keys, default=None):
    """Safely get nested dictionary values."""
    curr = data
    for k in keys:
        if isinstance(curr, dict) and k in curr:
            curr = curr[k]
        else:
            return default
    return curr

def verify_sar_avalanche_thermal_survey(traj, env_info, task_info):
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

    # --- Check 1: File exists and modified (10 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    
    if file_found and modified:
        score += 10
        feedback.append('Plan file exists and was modified (+10)')
    elif file_found:
        score += 5
        feedback.append('Plan file exists but was not modified during task (+5)')
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
        feedback.append(f'Could not parse plan JSON: {e} (+0 for remaining mission checks)')
        plan = {}

    survey_items = _find_survey_items(plan)
    survey_item = survey_items[0] if survey_items else {}
    camera_calc = survey_item.get('CameraCalc', survey_item.get('cameraCalc', {}))

    # --- Check 2: Survey polygon valid (10 pts) ---
    poly = survey_item.get('polygon', {})
    vertices = _count_polygon_vertices(poly)
    details['survey_vertices'] = vertices
    
    if vertices >= 3:
        score += 10
        feedback.append(f'Survey polygon has {vertices} vertices (+10)')
    else:
        feedback.append('Survey polygon missing or invalid (+0)')

    # --- Check 3: Custom Camera dimensions (15 pts) ---
    img_w = camera_calc.get('imageWidth')
    img_h = camera_calc.get('imageHeight')
    details['imageWidth'] = img_w
    details['imageHeight'] = img_h

    if img_w == 640 and img_h == 512:
        score += 15
        feedback.append('Camera dimensions correctly set to 640x512 (+15)')
    else:
        feedback.append(f'Camera dimensions incorrect: {img_w}x{img_h} (need 640x512) (+0)')

    # --- Check 4: Custom Camera optics (15 pts) ---
    sns_w = camera_calc.get('sensorWidth')
    sns_h = camera_calc.get('sensorHeight')
    focal = camera_calc.get('focalLength')
    details['sensorWidth'] = sns_w
    details['sensorHeight'] = sns_h
    details['focalLength'] = focal

    optics_ok = True
    if sns_w is None or abs(float(sns_w) - 10.88) > 0.1: optics_ok = False
    if sns_h is None or abs(float(sns_h) - 8.16) > 0.1: optics_ok = False
    if focal is None or abs(float(focal) - 13.0) > 0.1: optics_ok = False

    if optics_ok:
        score += 15
        feedback.append('Camera optics (sensor size & focal length) correct (+15)')
    else:
        feedback.append(f'Camera optics incorrect: {sns_w}x{sns_h}mm, FL={focal} (need 10.88x8.16mm, FL=13.0) (+0)')

    # --- Check 5: Survey Altitude (10 pts) ---
    alt = camera_calc.get('distanceToSurface')
    details['altitude'] = alt

    if alt is not None and abs(float(alt) - 80.0) < 1.0:
        score += 10
        feedback.append('Survey altitude set to 80m (+10)')
    else:
        feedback.append(f'Survey altitude incorrect: {alt}m (need 80m) (+0)')

    # --- Check 6: Survey Overlaps (10 pts) ---
    front_ov = camera_calc.get('FrontalOverlap', camera_calc.get('frontalOverlap'))
    side_ov = camera_calc.get('SideOverlap', camera_calc.get('sideOverlap'))
    details['frontal_overlap'] = front_ov
    details['side_overlap'] = side_ov

    overlaps_ok = True
    if front_ov is None or abs(float(front_ov) - 80.0) > 1.0: overlaps_ok = False
    if side_ov is None or abs(float(side_ov) - 70.0) > 1.0: overlaps_ok = False

    if overlaps_ok:
        score += 10
        feedback.append('Survey overlaps correct (Front: 80%, Side: 70%) (+10)')
    else:
        feedback.append(f'Survey overlaps incorrect: Front={front_ov}%, Side={side_ov}% (need 80/70) (+0)')

    # --- Check 7: WEATH_ENABLE parameter (15 pts) ---
    params = result.get('params', {})
    weath_en = params.get('WEATH_ENABLE')
    details['WEATH_ENABLE'] = weath_en

    if weath_en is not None and abs(float(weath_en) - 1.0) < 0.1:
        score += 15
        feedback.append('WEATH_ENABLE=1 configured correctly (+15)')
    else:
        feedback.append(f'WEATH_ENABLE={weath_en} (need 1) (+0)')

    # --- Check 8: RTL_SPEED parameter (15 pts) ---
    rtl_spd = params.get('RTL_SPEED')
    details['RTL_SPEED'] = rtl_spd

    if rtl_spd is not None and abs(float(rtl_spd) - 1500.0) < 1.0:
        score += 15
        feedback.append('RTL_SPEED=1500 configured correctly (+15)')
    else:
        feedback.append(f'RTL_SPEED={rtl_spd} (need 1500) (+0)')

    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }