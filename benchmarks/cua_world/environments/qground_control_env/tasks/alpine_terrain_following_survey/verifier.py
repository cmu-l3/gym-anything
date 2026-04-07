#!/usr/bin/env python3
"""Verifier for alpine_terrain_following_survey task.

Checks that the agent created a QGC survey mission with Terrain Following enabled.

Required parameters from briefing:
- File saved to /home/ga/Documents/QGC/glacier_survey.plan
- Mission contains a Survey ComplexItem
- followsTerrain == True  (CRITICAL)
- Altitude == 50 m
- FrontalOverlap == 80%
- SideOverlap == 80%

Scoring (100 pts total, pass = 75):
  15  File exists and was modified during task
  15  Survey ComplexItem found in plan
  40  Terrain Following enabled (Critical constraint)
  15  Altitude = 50m (±5m tolerance)
  15  Frontal & Side Overlaps = 80% (±5% tolerance)
"""

import json
import os
import tempfile


def _find_values(obj, key):
    """Recursively find all values for a given key in a nested dict/list."""
    results = []
    if isinstance(obj, dict):
        if key in obj:
            results.append(obj[key])
        for v in obj.values():
            results.extend(_find_values(v, key))
    elif isinstance(obj, list):
        for item in obj:
            results.extend(_find_values(item, key))
    return results


def _find_survey_items(plan):
    """Find all survey complex items in a QGC plan."""
    surveys = []
    mission = plan.get('mission', {})
    items = mission.get('items', [])
    for item in items:
        # Check standard complexItemType flag
        if item.get('complexItemType') == 'survey' or item.get('type') == 'ComplexItem':
            surveys.append(item)
        # Check nested structures for backward/forward QGC compatibility
        elif item.get('TransectStyleComplexItem', {}):
            surveys.append(item)
    return surveys


def verify_alpine_terrain_following_survey(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    plan_path = metadata.get('plan_path', '/home/ga/Documents/QGC/glacier_survey.plan')
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    
    target_alt = metadata.get('target_altitude_m', 50)
    target_overlap = metadata.get('target_overlap_pct', 80)
    alt_tol = metadata.get('altitude_tolerance_m', 5)
    over_tol = metadata.get('overlap_tolerance_pct', 5)

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

    # --- Check 1: File exists and modified (15 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    
    if file_found and modified:
        score += 15
        feedback.append('Plan file exists and was created/modified during task (+15)')
        details['file_valid'] = True
    elif file_found:
        feedback.append('Plan file exists but was NOT modified during the task (+0)')
        details['file_valid'] = False
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}
    else:
        feedback.append(f'Plan file not found at {plan_path} (+0)')
        details['file_valid'] = False
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Parse the plan file ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e} (+0 for remaining checks)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 2: Survey complex item found (15 pts) ---
    survey_items = _find_survey_items(plan)
    all_complex_types = _find_values(plan, 'complexItemType')

    has_survey = len(survey_items) > 0 or 'survey' in [str(t).lower() for t in all_complex_types]

    if has_survey:
        score += 15
        feedback.append('Survey ComplexItem found (+15)')
        details['survey_found'] = True
    else:
        feedback.append('No Survey ComplexItem found in plan (+0)')
        details['survey_found'] = False
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 3: Terrain Following Enabled (40 pts) ---
    # This is the most critical part of the task. Look for followsTerrain boolean.
    terrain_flags = _find_values(plan, 'followsTerrain')
    terrain_enabled = any(flag is True for flag in terrain_flags)
    
    if terrain_enabled:
        score += 40
        feedback.append('Terrain Following explicitly ENABLED ✓ (+40)')
        details['terrain_following'] = True
    else:
        feedback.append('Terrain Following is DISABLED or missing (CRITICAL FAILURE) (+0)')
        details['terrain_following'] = False

    # --- Check 4: Altitude = 50m (15 pts) ---
    altitudes = _find_values(plan, 'distanceToSurface')
    if not altitudes:
        altitudes = _find_values(plan, 'Altitude') # Fallback
        
    alt_correct = False
    for alt in altitudes:
        try:
            if abs(float(alt) - target_alt) <= alt_tol:
                alt_correct = True
                break
        except (TypeError, ValueError):
            continue

    if alt_correct:
        score += 15
        feedback.append(f'Altitude configured correctly (~{target_alt}m) (+15)')
        details['altitude_correct'] = True
    else:
        feedback.append(f'Altitude incorrect or not found (Expected ~{target_alt}m) (+0)')
        details['altitude_correct'] = False

    # --- Check 5: Overlaps = 80% (15 pts) ---
    frontal_overlaps = _find_values(plan, 'FrontalOverlap')
    side_overlaps = _find_values(plan, 'SideOverlap')
    
    front_ok = False
    for val in frontal_overlaps:
        try:
            if abs(float(val) - target_overlap) <= over_tol:
                front_ok = True
                break
        except (TypeError, ValueError):
            continue
            
    side_ok = False
    for val in side_overlaps:
        try:
            if abs(float(val) - target_overlap) <= over_tol:
                side_ok = True
                break
        except (TypeError, ValueError):
            continue

    if front_ok and side_ok:
        score += 15
        feedback.append(f'Frontal & Side overlaps configured correctly (~{target_overlap}%) (+15)')
        details['overlaps_correct'] = True
    elif front_ok or side_ok:
        score += 7
        feedback.append(f'Partial overlap points (Front={front_ok}, Side={side_ok}) (+7)')
        details['overlaps_correct'] = 'partial'
    else:
        feedback.append(f'Overlaps incorrect (Expected ~{target_overlap}%) (+0)')
        details['overlaps_correct'] = False

    # Final evaluation
    passed = score >= 75
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }