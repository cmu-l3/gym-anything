#!/usr/bin/env python3
"""Verifier for thermal_wildlife_survey_mission task.

Checks that the agent:
1. Created a survey mission plan.
2. Configured custom camera parameters for FLIR Boson 640.
3. Enabled "Hover and Capture" to prevent thermal motion blur.
4. Set the extended turnaround distance.

Scoring (100 pts total, pass = 75):
  10  File Exists & Valid JSON
  10  Survey Item Present
  15  Hover and Capture Enabled
  15  Turnaround Distance == 15.0
  15  Custom Sensor Size (Width 7.68, Height 6.14)
  10  Custom Image Resolution (640x512)
  10  Custom Focal Length (14.0)
  15  Altitude Correct (35.0)
"""

import json
import os
import tempfile

def _find_survey_item(plan):
    """Find the survey complex item in a QGC plan."""
    mission = plan.get('mission', {})
    items = mission.get('items', [])
    for item in items:
        # Check standard survey
        if item.get('complexItemType') == 'survey':
            return item
        # Check V4/V5 nested survey
        if item.get('type') == 'ComplexItem' and 'CameraCalc' in item:
            return item
    return None

def _get_val(item, key):
    """Safely extract a value that might be top-level or in CameraCalc."""
    if key in item:
        return item[key]
    if 'CameraCalc' in item and key in item['CameraCalc']:
        return item['CameraCalc'][key]
    return None

def verify_thermal_mission(traj, env_info, task_info):
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
        feedback.append('Plan file exists and was created/modified during task (+10)')
    elif file_found:
        feedback.append('Plan file exists but was NOT modified during task (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback)}
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback)}

    # --- Parse the plan JSON ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback)}

    # --- Check 2: Survey Item Present (10 pts) ---
    survey_item = _find_survey_item(plan)
    if survey_item:
        score += 10
        feedback.append('Survey item found (+10)')
    else:
        feedback.append('No Survey ComplexItem found in plan (+0)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback)}

    # --- Check 3: Hover and Capture Enabled (15 pts) ---
    # QGC stores this as boolean true/false or int 1/0
    hover_capture = _get_val(survey_item, 'hoverAndCapture')
    details['hover_capture'] = hover_capture
    if hover_capture is True or str(hover_capture) == '1' or str(hover_capture).lower() == 'true':
        score += 15
        feedback.append('Hover and Capture is enabled ✓ (+15)')
    else:
        feedback.append('Hover and Capture is NOT enabled (+0)')

    # --- Check 4: Turnaround Distance == 15.0 (15 pts) ---
    turnaround = _get_val(survey_item, 'turnAroundDistance')
    details['turnaround'] = turnaround
    try:
        if abs(float(turnaround) - metadata.get('expected_turnaround', 15.0)) <= 1.0:
            score += 15
            feedback.append(f'Turnaround distance correct ({turnaround}m) ✓ (+15)')
        else:
            feedback.append(f'Turnaround distance wrong: {turnaround}m (expected 15.0) (+0)')
    except (TypeError, ValueError):
        feedback.append('Turnaround distance missing or invalid (+0)')

    # --- Check 5: Custom Sensor Size (15 pts) ---
    sensor_width = _get_val(survey_item, 'SensorWidth')
    sensor_height = _get_val(survey_item, 'SensorHeight')
    details['sensor_w'] = sensor_width
    details['sensor_h'] = sensor_height
    try:
        w_ok = abs(float(sensor_width) - metadata.get('expected_sensor_width', 7.68)) <= 0.1
        h_ok = abs(float(sensor_height) - metadata.get('expected_sensor_height', 6.14)) <= 0.1
        if w_ok and h_ok:
            score += 15
            feedback.append(f'Sensor size correct ({sensor_width}x{sensor_height}mm) ✓ (+15)')
        else:
            feedback.append(f'Sensor size wrong: {sensor_width}x{sensor_height} (expected 7.68x6.14) (+0)')
    except (TypeError, ValueError):
        feedback.append('Sensor size missing or invalid (+0)')

    # --- Check 6: Custom Image Resolution (10 pts) ---
    img_width = _get_val(survey_item, 'ImageWidth')
    img_height = _get_val(survey_item, 'ImageHeight')
    details['img_w'] = img_width
    details['img_h'] = img_height
    try:
        if int(img_width) == 640 and int(img_height) == 512:
            score += 10
            feedback.append(f'Image resolution correct ({img_width}x{img_height}) ✓ (+10)')
        else:
            feedback.append(f'Image resolution wrong: {img_width}x{img_height} (expected 640x512) (+0)')
    except (TypeError, ValueError):
        feedback.append('Image resolution missing or invalid (+0)')

    # --- Check 7: Custom Focal Length (10 pts) ---
    focal_len = _get_val(survey_item, 'FocalLength')
    details['focal_len'] = focal_len
    try:
        if abs(float(focal_len) - metadata.get('expected_focal_length', 14.0)) <= 0.5:
            score += 10
            feedback.append(f'Focal length correct ({focal_len}mm) ✓ (+10)')
        else:
            feedback.append(f'Focal length wrong: {focal_len}mm (expected 14.0) (+0)')
    except (TypeError, ValueError):
        feedback.append('Focal length missing or invalid (+0)')

    # --- Check 8: Altitude Correct (15 pts) ---
    # Altitude can be in 'distanceToSurface' or top-level 'Altitude'
    alt = _get_val(survey_item, 'distanceToSurface')
    if alt is None:
        alt = survey_item.get('Altitude')
    details['altitude'] = alt
    
    try:
        if abs(float(alt) - metadata.get('expected_altitude', 35.0)) <= 1.0:
            score += 15
            feedback.append(f'Altitude correct ({alt}m) ✓ (+15)')
        else:
            feedback.append(f'Altitude wrong: {alt}m (expected 35.0) (+0)')
    except (TypeError, ValueError):
        feedback.append('Altitude missing or invalid (+0)')

    passed = score >= 75
    if passed:
        feedback.append('PASS: Thermal survey configuration meets all mission critical requirements.')
    else:
        feedback.append(f'FAIL: Score {score}/100. Must reach 75 to pass.')

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }