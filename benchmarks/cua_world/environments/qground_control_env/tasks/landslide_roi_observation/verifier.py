#!/usr/bin/env python3
"""
Verifier for landslide_roi_observation task.

The agent must create a QGC mission plan with specific navigation and camera targeting features.

Requirements & Scoring (100 pts total, Pass Threshold: 70):
1. Plan file exists at /home/ga/Documents/QGC/landslide_recon.plan (10 pts)
2. File was created/modified during the task window (5 pts)
3. DO_SET_ROI / DO_SET_ROI_LOCATION command present (20 pts)
4. ROI target coordinates match required (47.3990, 8.5475) within ±0.001 (15 pts)
5. At least 2 LOITER_TURNS commands present (15 pts)
6. Loiter commands configured for exactly 2 turns (5 pts)
7. At least 3 NAV_WAYPOINT items present (15 pts)
8. RTL command present at the end (10 pts)
9. Mission item count is reasonable (>5 items) (5 pts)

A successful run must master the ROI functionality (mandatory for high score).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MAV_CMD constants
CMD_NAV_WAYPOINT = 16
CMD_NAV_LOITER_TURNS = 18
CMD_NAV_RETURN_TO_LAUNCH = 20
CMD_DO_SET_ROI_LOCATION = 195
CMD_DO_SET_ROI = 201

def extract_coordinate(item):
    """
    Extract coordinate (lat, lon) from a QGC plan item.
    QGC stores coordinates in the 'coordinate' array or in 'params' [4] and [5].
    """
    # 1. Check 'coordinate' array directly
    coord = item.get('coordinate')
    if isinstance(coord, list) and len(coord) >= 2:
        lat, lon = coord[0], coord[1]
        if lat is not None and lon is not None and lat != 0.0 and lon != 0.0:
            return float(lat), float(lon)
            
    # 2. Check 'params' array (usually params[4] = lat, params[5] = lon for ROI)
    params = item.get('params', [])
    if len(params) >= 7:
        lat, lon = params[4], params[5]
        if lat is not None and lon is not None and lat != 0.0 and lon != 0.0:
            return float(lat), float(lon)
            
    return None, None

def verify_landslide_roi_observation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    target_lat = metadata.get('target_roi_lat', 47.3990)
    target_lon = metadata.get('target_roi_lon', 8.5475)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.001)

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

    # 1. Check file exists (10 pts)
    file_found = result.get('file_found', False)
    if file_found:
        score += 10
        feedback.append('Plan file exists (+10)')
        details['file_exists'] = True
    else:
        feedback.append('Plan file not found at expected path (+0)')
        details['file_exists'] = False
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    # 2. Modified during task (5 pts)
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File modified during task (+5)')
        details['modified'] = True
    else:
        feedback.append('File not modified during task (+0)')
        details['modified'] = False

    # Parse the plan JSON
    plan_content_raw = result.get('plan_content', '')
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

    # Extract mission items
    mission = plan.get('mission', {})
    items = mission.get('items', [])
    details['total_items'] = len(items)

    # 3. DO_SET_ROI command present (20 pts)
    roi_items = [it for it in items if it.get('command') in [CMD_DO_SET_ROI_LOCATION, CMD_DO_SET_ROI]]
    details['roi_commands_count'] = len(roi_items)

    if len(roi_items) > 0:
        score += 20
        feedback.append('DO_SET_ROI command found (+20)')
        
        # 4. ROI Coordinates accurate (15 pts)
        roi_lat, roi_lon = extract_coordinate(roi_items[0])
        details['roi_lat'] = roi_lat
        details['roi_lon'] = roi_lon
        
        if roi_lat is not None and roi_lon is not None:
            lat_diff = abs(roi_lat - target_lat)
            lon_diff = abs(roi_lon - target_lon)
            if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
                score += 15
                feedback.append(f'ROI target coordinates accurate ({roi_lat:.4f}, {roi_lon:.4f}) (+15)')
            else:
                feedback.append(f'ROI coordinates ({roi_lat:.4f}, {roi_lon:.4f}) out of tolerance (expected {target_lat}, {target_lon}) (+0)')
        else:
            feedback.append('Could not extract valid ROI coordinates (+0)')
    else:
        feedback.append('DO_SET_ROI command NOT found (+0)')

    # 5. At least 2 LOITER_TURNS commands present (15 pts)
    loiter_items = [it for it in items if it.get('command') == CMD_NAV_LOITER_TURNS]
    details['loiter_commands_count'] = len(loiter_items)

    if len(loiter_items) >= 2:
        score += 15
        feedback.append(f'{len(loiter_items)} LOITER_TURNS commands found (+15)')
        
        # 6. Loiter turns count correct (5 pts)
        correct_turns = 0
        for it in loiter_items:
            params = it.get('params', [])
            # In QGC, param 1 (index 0) is the Turns parameter for LOITER_TURNS
            if len(params) > 0 and params[0] is not None:
                try:
                    turns = int(params[0])
                    if turns == 2:
                        correct_turns += 1
                except (ValueError, TypeError):
                    pass
        
        if correct_turns >= 2:
            score += 5
            feedback.append('Loiter commands correctly configured for 2 turns (+5)')
        elif correct_turns == 1:
            score += 2
            feedback.append('Only 1 Loiter command correctly configured for 2 turns (+2)')
        else:
            feedback.append('Loiter commands missing or incorrect turn count (+0)')
            
    elif len(loiter_items) == 1:
        score += 7
        feedback.append(f'Only 1 LOITER_TURNS command found (expected 2) (+7)')
    else:
        feedback.append('No LOITER_TURNS commands found (+0)')

    # 7. At least 3 NAV_WAYPOINT items (15 pts)
    nav_items = [it for it in items if it.get('command') == CMD_NAV_WAYPOINT]
    details['waypoint_count'] = len(nav_items)

    if len(nav_items) >= 3:
        score += 15
        feedback.append(f'{len(nav_items)} NAV_WAYPOINT commands found (+15)')
    elif len(nav_items) > 0:
        score += 7
        feedback.append(f'Only {len(nav_items)} NAV_WAYPOINT found (expected >=3) (+7)')
    else:
        feedback.append('No standard NAV_WAYPOINT commands found (+0)')

    # 8. RTL command present (10 pts)
    rtl_items = [it for it in items if it.get('command') == CMD_NAV_RETURN_TO_LAUNCH]
    details['rtl_count'] = len(rtl_items)

    if len(rtl_items) > 0:
        score += 10
        feedback.append('RTL command found (+10)')
    else:
        feedback.append('RTL command NOT found (+0)')

    # 9. Mission item count reasonable (5 pts)
    # A valid mission should have takeoff(1) + waypoints(3) + loiters(2) + ROI(1) + RTL(1) = 8 items min.
    if len(items) >= 6 and len(items) <= 25:
        score += 5
        feedback.append(f'Reasonable mission item count: {len(items)} (+5)')
    else:
        feedback.append(f'Unreasonable item count: {len(items)} (expected 6-25) (+0)')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }