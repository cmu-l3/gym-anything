#!/usr/bin/env python3
"""Verifier for soil_sampling_loiter_mission task.

Checks that the agent read coordinates from the CSV and created a valid mission
with Loiter (Time) waypoints and correct bookend commands (Takeoff/RTL).

Verification Criteria & Scoring (100 pts total, Pass = 70):
  10  Plan file exists and is valid JSON
   5  File modified during task (anti-gaming)
  10  Takeoff command present (cmd=22)
  30  All 6 coordinates matched within tolerance (5 pts each)
  15  >=4 matched points have Loiter Time >= 20s (cmd=19, param1>=20)
  10  All 6 matched points have Loiter Time >= 20s (bonus)
  10  RTL command present (cmd=20)
  10  Altitude in safe range [15, 50]m for >= 4 waypoints
"""

import json
import os
import tempfile
import math

# MAVLink Command IDs
CMD_LOITER_TIME = 19
CMD_RTL = 20
CMD_TAKEOFF = 22

def _get_item_coords(item):
    """Extract lat/lon from a mission item."""
    params = item.get('params', [])
    if len(params) >= 7 and params[4] is not None and params[5] is not None:
        try:
            lat = float(params[4])
            lon = float(params[5])
            if lat != 0.0 or lon != 0.0:  # Ignore 0,0 which is default/empty
                return (lat, lon)
        except (TypeError, ValueError):
            pass
    return None

def _get_item_altitude(item):
    """Extract altitude from an item."""
    alt = item.get('Altitude')
    if alt is not None:
        try:
            return float(alt)
        except (TypeError, ValueError):
            pass
    params = item.get('params', [])
    if len(params) >= 7 and params[6] is not None:
        try:
            return float(params[6])
        except (TypeError, ValueError):
            pass
    return None

def _get_loiter_time(item):
    """Extract loiter time in seconds (param 1 for CMD 19)."""
    params = item.get('params', [])
    if item.get('command') == CMD_LOITER_TIME and len(params) >= 1:
        try:
            return float(params[0])
        except (TypeError, ValueError):
            pass
    return 0.0

def verify_soil_sampling_loiter_mission(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    target_coords = metadata.get('target_coords', [])
    coord_tol = metadata.get('coord_tolerance', 0.0005)
    min_loiter = metadata.get('min_loiter_time_s', 20)
    alt_min = metadata.get('alt_min', 15)
    alt_max = metadata.get('alt_max', 50)

    # Read exported result
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

    # --- Check 1 & 2: File exists and modified (15 pts) ---
    if result.get('file_found', False):
        score += 10
        feedback.append('Plan file found (+10)')
        if result.get('modified_during_task', False):
            score += 5
            feedback.append('File modified during task (+5)')
        else:
            feedback.append('File existed prior to task (not modified) (+0)')
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Parse JSON ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    
    try:
        plan = json.loads(plan_content_raw)
        items = plan.get('mission', {}).get('items', [])
        details['num_items'] = len(items)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    if not items:
        feedback.append('Plan contains no mission items (+0)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Check 3: Takeoff command (10 pts) ---
    has_takeoff = any(item.get('command') == CMD_TAKEOFF for item in items)
    if has_takeoff:
        score += 10
        feedback.append('Takeoff command found (+10)')
    else:
        feedback.append('Takeoff command missing (+0)')

    # --- Check 4: RTL command (10 pts) ---
    has_rtl = any(item.get('command') == CMD_RTL for item in items)
    if has_rtl:
        score += 10
        feedback.append('RTL command found (+10)')
    else:
        feedback.append('RTL command missing (+0)')

    # --- Check 5: Coordinates matched (30 pts, 5 per point) ---
    matched_coords = 0
    loiters_at_matched = 0
    safe_alts_count = 0

    for idx, (t_lat, t_lon) in enumerate(target_coords):
        # Look for any item close to this target
        match_found = False
        loiter_valid = False
        alt_valid = False

        for item in items:
            coords = _get_item_coords(item)
            if coords:
                lat, lon = coords
                # Check distance
                if abs(lat - t_lat) <= coord_tol and abs(lon - t_lon) <= coord_tol:
                    match_found = True
                    # Check if this specific item has the loiter time
                    if _get_loiter_time(item) >= min_loiter:
                        loiter_valid = True
                    
                    # Check altitude safety
                    alt = _get_item_altitude(item)
                    if alt is not None and alt_min <= alt <= alt_max:
                        alt_valid = True

        if match_found:
            matched_coords += 1
            score += 5
            feedback.append(f'SP-0{idx+1} coordinates matched (+5)')
            if loiter_valid:
                loiters_at_matched += 1
            if alt_valid:
                safe_alts_count += 1
        else:
            feedback.append(f'SP-0{idx+1} coordinates NOT matched (+0)')

    details['matched_coords'] = matched_coords
    details['loiters_at_matched'] = loiters_at_matched
    details['safe_alts_count'] = safe_alts_count

    # --- Check 6: Loiter times (25 pts max) ---
    if loiters_at_matched >= 4:
        score += 15
        feedback.append(f'>=4 sampling points have >=20s loiter time (+15)')
        if loiters_at_matched == len(target_coords):
            score += 10
            feedback.append('All 6 sampling points have correct loiter time (+10 bonus)')
    elif loiters_at_matched > 0:
        feedback.append(f'Only {loiters_at_matched} sampling points have correct loiter (+0/15)')
    else:
        feedback.append('No sampling points have correct loiter time (+0/25)')

    # --- Check 7: Altitude safety (10 pts) ---
    # Give credit if at least 4 items (could be Takeoff + 3 waypoints, etc.) are in safe bound
    total_safe_alts = sum(1 for i in items if _get_item_altitude(i) is not None and alt_min <= _get_item_altitude(i) <= alt_max)
    if total_safe_alts >= 4:
        score += 10
        feedback.append(f'Altitudes safely bounded [{alt_min}-{alt_max}m] (+10)')
    else:
        feedback.append(f'Unsafe or missing altitudes found (+0)')

    passed = score >= 70

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }