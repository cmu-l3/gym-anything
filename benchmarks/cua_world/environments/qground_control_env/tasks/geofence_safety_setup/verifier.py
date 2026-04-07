#!/usr/bin/env python3
"""Verifier for geofence_safety_setup task.

Checks that the agent:
1. Created a plan file with inclusion polygon (>=5 vertices)
2. Added an exclusion zone (circle or polygon)
3. Added >=2 rally points
4. Set FENCE_ACTION=1 and RTL_ALT=2500

Scoring (100 pts total, pass = 70):
  10  File exists
  10  File modified during task
  25  Inclusion polygon with >=5 vertices
  20  Exclusion zone present (circle or polygon with inclusion=false)
  20  >=2 rally points
   5  FENCE_ACTION == 1
  10  RTL_ALT == 2500
"""

import json
import os
import tempfile
import math


def _count_polygon_vertices(polygon):
    """Count vertices in a QGC polygon (path or polygon key)."""
    path = polygon.get('path', polygon.get('polygon', polygon.get('vertices', [])))
    if isinstance(path, list):
        return len(path)
    return 0


def verify_geofence_safety_setup(traj, env_info, task_info):
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

    # --- Check 1: File exists (10 pts) ---
    file_found = result.get('file_found', False)
    if file_found:
        score += 10
        feedback.append('Plan file exists (+10)')
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 2: Modified during task (10 pts) ---
    if result.get('modified_during_task', False):
        score += 10
        feedback.append('File modified during task (+10)')
    else:
        feedback.append('File not modified during task (+0)')

    # --- Parse plan ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Cannot parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    geofence = plan.get('geoFence', {})
    polygons = geofence.get('polygons', [])
    circles = geofence.get('circles', [])
    rally_section = plan.get('rallyPoints', {})
    rally_pts = rally_section.get('points', [])

    # --- Check 3: Inclusion polygon with >=5 vertices (25 pts) ---
    inclusion_polys = [p for p in polygons if p.get('inclusion', False) is True]
    best_incl_verts = max((_count_polygon_vertices(p) for p in inclusion_polys), default=0)
    details['inclusion_polygons'] = len(inclusion_polys)
    details['best_inclusion_vertices'] = best_incl_verts

    if best_incl_verts >= 5:
        score += 25
        feedback.append(f'Inclusion polygon with {best_incl_verts} vertices (+25)')
    elif best_incl_verts >= 3:
        score += 10
        feedback.append(f'Inclusion polygon with only {best_incl_verts} vertices (need >=5) (+10 partial)')
    else:
        feedback.append(f'No valid inclusion polygon (>=5 vertices) found (+0)')

    # --- Check 4: Exclusion zone (20 pts) ---
    exclusion_polys = [p for p in polygons if p.get('inclusion', True) is False]
    exclusion_circles = [c for c in circles if c.get('inclusion', True) is False]
    has_exclusion = len(exclusion_polys) > 0 or len(exclusion_circles) > 0
    details['exclusion_polygons'] = len(exclusion_polys)
    details['exclusion_circles'] = len(exclusion_circles)

    if has_exclusion:
        score += 20
        feedback.append(f'Exclusion zone found (polygons:{len(exclusion_polys)}, circles:{len(exclusion_circles)}) (+20)')
    else:
        feedback.append('No exclusion zone found (+0)')

    # --- Check 5: >=2 rally points (20 pts) ---
    n_rally = len(rally_pts)
    details['rally_point_count'] = n_rally

    if n_rally >= 2:
        score += 20
        feedback.append(f'{n_rally} rally points found (+20)')
    elif n_rally == 1:
        score += 8
        feedback.append(f'Only 1 rally point found (need >=2) (+8 partial)')
    else:
        feedback.append('No rally points found (+0)')

    # --- Check 6: FENCE_ACTION == 1 (5 pts) ---
    params = result.get('params', {})
    fence_action = params.get('FENCE_ACTION')
    details['FENCE_ACTION'] = fence_action

    if fence_action is not None and round(float(fence_action)) == 1:
        score += 5
        feedback.append(f'FENCE_ACTION=1 (+5)')
    else:
        feedback.append(f'FENCE_ACTION={fence_action} (need 1) (+0)')

    # --- Check 7: RTL_ALT == 2500 (10 pts) ---
    rtl_alt = params.get('RTL_ALT')
    details['RTL_ALT'] = rtl_alt

    if rtl_alt is not None and abs(float(rtl_alt) - 2500.0) < 50.0:
        score += 10
        feedback.append(f'RTL_ALT=2500 (+10)')
    else:
        feedback.append(f'RTL_ALT={rtl_alt} (need 2500) (+0)')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }
