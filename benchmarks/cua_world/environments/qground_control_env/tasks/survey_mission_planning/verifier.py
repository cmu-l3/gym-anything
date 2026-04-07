#!/usr/bin/env python3
"""Verifier for survey_mission_planning task.

Checks that the agent created a QGC survey mission plan that meets the
photogrammetric specifications in the requirements document:
- Sony a5100 camera, 16mm lens, target GSD = 4 cm/px
- Required altitude: ~163.4 m (accept 140–190 m)
- Frontal overlap: 75% (accept 65–85%)
- Side overlap: 65% (accept 55–75%)

Scoring (100 pts total, pass = 60):
  15  File exists at expected path
  10  File modified during task
  30  Survey ComplexItem found in plan
  25  Altitude in acceptable range [140, 190] m
  10  FrontalOverlap in acceptable range [60, 90]
  10  SideOverlap in acceptable range [50, 80]
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
    items = []
    # Check mission.items
    mission = plan.get('mission', {})
    items = mission.get('items', [])
    for item in items:
        if item.get('complexItemType') == 'survey' or item.get('type') == 'ComplexItem':
            surveys.append(item)
        # Also check nested TransectStyleComplexItem
        nested = item.get('TransectStyleComplexItem', {})
        if nested:
            surveys.append(item)
    return surveys


def verify_survey_mission_planning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    plan_path = metadata.get('plan_path', '/home/ga/Documents/QGC/field_survey.plan')
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Get the export result (file metadata)
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

    # --- Check 1: File exists (15 pts) ---
    file_found = result.get('file_found', False)
    if file_found:
        score += 15
        feedback.append('Plan file exists (+15)')
        details['file_exists'] = True
    else:
        feedback.append(f'Plan file not found at {plan_path} (+0)')
        details['file_exists'] = False
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    # --- Check 2: Modified during task (10 pts) ---
    if result.get('modified_during_task', False):
        score += 10
        feedback.append('File modified during task (+10)')
        details['modified'] = True
    else:
        feedback.append('File not modified during task (+0)')
        details['modified'] = False

    # --- Parse the plan file ---
    plan_content_raw = result.get('plan_content', '')
    # Unescape \\n -> \n as per note 13
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e} (+0 for remaining checks)')
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    # --- Check 3: Survey complex item found (30 pts) ---
    survey_items = _find_survey_items(plan)
    # Also look for complexItemType anywhere in the tree
    all_complex_types = _find_values(plan, 'complexItemType')

    has_survey = len(survey_items) > 0 or 'survey' in [str(t).lower() for t in all_complex_types]

    if has_survey:
        score += 30
        feedback.append('Survey ComplexItem found (+30)')
        details['survey_found'] = True
    else:
        feedback.append('No Survey ComplexItem found in plan (+0)')
        details['survey_found'] = False
        # Can still check mission items for altitude if simple items
        # but skip overlap checks
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    # Get the survey item (first one)
    survey_item = survey_items[0] if survey_items else {}

    # --- Check 4: Altitude in [140, 190] m (25 pts) ---
    # Altitude may be in CameraCalc > distanceToSurface or top-level Altitude
    alt_candidates = _find_values(plan, 'distanceToSurface') + _find_values(plan, 'Altitude')
    # Filter to plausible survey altitudes (50–300 m) from survey items
    survey_alts = []
    for a in alt_candidates:
        try:
            a_f = float(a)
            if 50.0 <= a_f <= 500.0:
                survey_alts.append(a_f)
        except (TypeError, ValueError):
            pass

    details['altitude_candidates'] = survey_alts[:5]

    # Check if any altitude is in [140, 190]
    altitude_ok = any(140.0 <= a <= 190.0 for a in survey_alts)
    if altitude_ok:
        score += 25
        matching = [a for a in survey_alts if 140.0 <= a <= 190.0]
        feedback.append(f'Altitude in range [140,190]m: {matching[0]:.1f}m (+25)')
        details['altitude_ok'] = True
        details['altitude_value'] = matching[0]
    else:
        feedback.append(f'Altitude not in [140,190]m range; found: {survey_alts[:3]} (+0)')
        details['altitude_ok'] = False

    # --- Check 5: FrontalOverlap in [60, 90] (10 pts) ---
    frontal_vals = _find_values(plan, 'FrontalOverlap')
    frontal_ok = any(60.0 <= float(v) <= 90.0 for v in frontal_vals if v is not None)
    if frontal_ok:
        score += 10
        matching = [v for v in frontal_vals if v is not None and 60.0 <= float(v) <= 90.0]
        feedback.append(f'FrontalOverlap in range: {matching[0]} (+10)')
        details['frontal_overlap_ok'] = True
    else:
        feedback.append(f'FrontalOverlap not in [60,90]: {frontal_vals[:3]} (+0)')
        details['frontal_overlap_ok'] = False

    # --- Check 6: SideOverlap in [50, 80] (10 pts) ---
    side_vals = _find_values(plan, 'SideOverlap')
    side_ok = any(50.0 <= float(v) <= 80.0 for v in side_vals if v is not None)
    if side_ok:
        score += 10
        matching = [v for v in side_vals if v is not None and 50.0 <= float(v) <= 80.0]
        feedback.append(f'SideOverlap in range: {matching[0]} (+10)')
        details['side_overlap_ok'] = True
    else:
        feedback.append(f'SideOverlap not in [50,80]: {side_vals[:3]} (+0)')
        details['side_overlap_ok'] = False

    # Require altitude to be correct (major spec) — can't pass on overlaps alone.
    # Max without altitude = 15+10+30+10+10 = 75 < 80, so threshold enforces altitude.
    passed = score >= 80
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }
