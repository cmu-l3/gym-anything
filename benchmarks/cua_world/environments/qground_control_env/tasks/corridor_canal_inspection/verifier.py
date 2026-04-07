#!/usr/bin/env python3
"""Verifier for corridor_canal_inspection task.

Checks that the agent created a QGC Corridor Scan mission plan that meets the specs:
- Uses CorridorScan complexItemType.
- Has a polyline path with >=3 vertices.
- CorridorWidth in acceptable range [60, 100] m (target 80).
- Altitude in acceptable range [45, 75] m (target ~61).
- FrontalOverlap in acceptable range [60, 85]% (target 70).
- SideOverlap in acceptable range [50, 75]% (target 60).

Scoring (100 pts total, pass = 70):
  10  File exists at expected path
  10  File modified during task
  25  CorridorScan complex item found
  15  >=3 path vertices (partial 8 pts for 2 vertices)
  15  CorridorWidth in [60, 100] m
  15  Altitude in [45, 75] m
   5  FrontalOverlap in [60, 85]
   5  SideOverlap in [50, 75]
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _find_corridor_scan_items(plan):
    """Find all Corridor Scan complex items in a QGC plan recursively."""
    items = []
    def _search(obj):
        if isinstance(obj, dict):
            ct = obj.get('complexItemType', '')
            if isinstance(ct, str) and ct.lower() == 'corridorscan':
                items.append(obj)
            for v in obj.values():
                _search(v)
        elif isinstance(obj, list):
            for item in obj:
                _search(item)
    _search(plan)
    return items

def _get_number(obj, keys):
    """Search for the first occurrence of any key in keys recursively."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if str(k).lower() in [key.lower() for key in keys]:
                try:
                    return float(v)
                except (TypeError, ValueError):
                    pass
        for v in obj.values():
            res = _get_number(v, keys)
            if res is not None:
                return res
    elif isinstance(obj, list):
        for item in obj:
            res = _get_number(item, keys)
            if res is not None:
                return res
    return None

def _get_path_length(obj):
    """Find the longest list under keys like 'path', 'polygon', 'polyline'."""
    max_len = 0
    if isinstance(obj, dict):
        for k, v in obj.items():
            if str(k).lower() in ['path', 'polygon', 'polyline', 'vertices']:
                if isinstance(v, list):
                    max_len = max(max_len, len(v))
        for v in obj.values():
            max_len = max(max_len, _get_path_length(v))
    elif isinstance(obj, list):
        for item in obj:
            max_len = max(max_len, _get_path_length(item))
    return max_len

def verify_corridor_canal_inspection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    plan_path = metadata.get('plan_path', '/home/ga/Documents/QGC/canal_inspection.plan')
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Copy and read the export result
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

    # --- 1. Check File Exists (10 pts) ---
    if result.get('file_found', False):
        score += 10
        feedback.append('Plan file exists (+10)')
        details['file_exists'] = True
    else:
        feedback.append(f'Plan file not found at {plan_path} (+0)')
        details['file_exists'] = False
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- 2. Check File Modified During Task (10 pts) ---
    if result.get('modified_during_task', False):
        score += 10
        feedback.append('File modified during task (+10)')
        details['modified'] = True
    else:
        feedback.append('File not modified during task (+0)')
        details['modified'] = False

    # --- Parse the plan file JSON ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e} (+0 for remaining checks)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- 3. Check CorridorScan Complex Item Found (25 pts) ---
    corridor_items = _find_corridor_scan_items(plan)
    if corridor_items:
        score += 25
        feedback.append('CorridorScan complex item found (+25)')
        details['corridor_found'] = True
    else:
        feedback.append('No CorridorScan complex item found in plan (+0)')
        details['corridor_found'] = False
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    corridor_item = corridor_items[0]

    # --- 4. Check Path Vertices (15 pts) ---
    path_len = _get_path_length(corridor_item)
    details['path_vertices'] = path_len
    if path_len >= 3:
        score += 15
        feedback.append(f'Corridor path has {path_len} vertices (+15)')
    elif path_len == 2:
        score += 8
        feedback.append(f'Corridor path has only 2 vertices (need >=3) (+8)')
    else:
        feedback.append(f'Corridor path missing or has <2 vertices (+0)')

    # --- 5. Check Corridor Width (15 pts) ---
    width = _get_number(corridor_item, ['CorridorWidth', 'corridorWidth'])
    details['corridor_width'] = width
    if width is not None and 60 <= width <= 100:
        score += 15
        feedback.append(f'Corridor width = {width:.1f} m (+15)')
    elif width is not None:
        feedback.append(f'Corridor width = {width:.1f} m (expected 60-100) (+0)')
    else:
        feedback.append('Corridor width not found (+0)')

    # --- 6. Check Altitude (15 pts) ---
    altitude = _get_number(corridor_item, ['distanceToSurface', 'Altitude', 'altitude'])
    details['altitude'] = altitude
    if altitude is not None and 45 <= altitude <= 75:
        score += 15
        feedback.append(f'Altitude = {altitude:.1f} m (+15)')
    elif altitude is not None:
        feedback.append(f'Altitude = {altitude:.1f} m (expected 45-75) (+0)')
    else:
        feedback.append('Altitude not found (+0)')

    # --- 7. Check Overlaps (10 pts) ---
    frontal = _get_number(corridor_item, ['FrontalOverlap', 'frontalOverlap'])
    details['frontal_overlap'] = frontal
    if frontal is not None and 60 <= frontal <= 85:
        score += 5
        feedback.append(f'Frontal overlap = {frontal:.0f}% (+5)')
    else:
        feedback.append(f'Frontal overlap = {frontal} (expected 60-85) (+0)')

    side = _get_number(corridor_item, ['SideOverlap', 'sideOverlap'])
    details['side_overlap'] = side
    if side is not None and 50 <= side <= 75:
        score += 5
        feedback.append(f'Side overlap = {side:.0f}% (+5)')
    else:
        feedback.append(f'Side overlap = {side} (expected 50-75) (+0)')

    passed = score >= 70
    details['total_score'] = score

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }