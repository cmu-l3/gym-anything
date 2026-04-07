#!/usr/bin/env python3
"""Verifier for structure_scan_silo_inspection task.

Checks that the agent created a QGC mission plan containing a Structure Scan
with the required parameters matching the inspection brief:
- Structure Scan complex item present
- Structure Height: ~28m (accept >= 25m)
- Layers: >= 3
- Gimbal Pitch: 0 degrees (accept [-10, 10])
- Starts with Takeoff (command 22)
- Ends with RTL (command 20)

Scoring (100 pts total, pass = 70):
  10  File exists at expected path
   5  File modified during task
  30  StructureScan ComplexItem found in plan
  15  Structure height >= 25 m
  15  Layers >= 3
  10  Gimbal pitch in [-10, 10] degrees
   5  Takeoff command present
  10  RTL command present
"""

import json
import os
import tempfile


def _find_structure_scan(obj):
    """Recursively search for a StructureScan complex item in the plan dict."""
    if isinstance(obj, dict):
        ctype = str(obj.get('complexItemType', '')).lower()
        if ctype == 'structurescan':
            return obj
        for v in obj.values():
            res = _find_structure_scan(v)
            if res:
                return res
    elif isinstance(obj, list):
        for item in obj:
            res = _find_structure_scan(item)
            if res:
                return res
    return None


def _has_command(obj, cmd_id):
    """Recursively check if a specific MAVLink command exists in the plan."""
    if isinstance(obj, dict):
        if obj.get('command') == cmd_id:
            return True
        for v in obj.values():
            if _has_command(v, cmd_id):
                return True
    elif isinstance(obj, list):
        for item in obj:
            if _has_command(item, cmd_id):
                return True
    return False


def verify_structure_scan_silo_inspection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    plan_path = metadata.get('plan_path', '/home/ga/Documents/QGC/silo_inspection.plan')
    result_file = metadata.get('result_file', '/tmp/task_result.json')

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

    # --- Check 1: File exists (10 pts) ---
    file_found = result.get('file_found', False)
    if file_found:
        score += 10
        feedback.append('Plan file exists (+10)')
        details['file_exists'] = True
    else:
        feedback.append(f'Plan file not found at {plan_path} (+0)')
        details['file_exists'] = False
        return {
            'passed': False, 'score': score,
            'feedback': ' | '.join(feedback), 'details': details
        }

    # --- Check 2: Modified during task (5 pts) ---
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File modified during task (+5)')
        details['modified'] = True
    else:
        feedback.append('File not modified during task (+0)')
        details['modified'] = False

    # --- Parse the plan file ---
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

    # --- Check 3: Structure Scan item present (30 pts) ---
    scan_item = _find_structure_scan(plan)
    
    if scan_item:
        score += 30
        feedback.append('StructureScan ComplexItem found (+30)')
        details['structure_scan_found'] = True
    else:
        feedback.append('No StructureScan ComplexItem found in plan (+0)')
        details['structure_scan_found'] = False
        # Without a structure scan item, remaining parameter checks can't pass
        # We will still check for Takeoff and RTL though
        pass

    # Extract parameters if scan item was found
    if scan_item:
        # Check 4: Structure height >= 25 m (15 pts)
        try:
            height = float(scan_item.get('StructureHeight', 0))
            details['structure_height'] = height
            if height >= 25:
                score += 15
                feedback.append(f'Structure height = {height}m (>= 25m) (+15)')
            else:
                feedback.append(f'Structure height = {height}m (need >= 25m) (+0)')
        except (TypeError, ValueError):
            feedback.append('Could not read StructureHeight (+0)')

        # Check 5: Layers >= 3 (15 pts)
        try:
            layers = int(scan_item.get('Layers', 0))
            details['layers'] = layers
            if layers >= 3:
                score += 15
                feedback.append(f'Layers = {layers} (>= 3) (+15)')
            else:
                feedback.append(f'Layers = {layers} (need >= 3) (+0)')
        except (TypeError, ValueError):
            feedback.append('Could not read Layers (+0)')

        # Check 6: Gimbal pitch in [-10, 10] (10 pts)
        try:
            pitch = float(scan_item.get('GimbalPitch', -90)) # defaults usually point down (-90)
            details['gimbal_pitch'] = pitch
            if -10 <= pitch <= 10:
                score += 10
                feedback.append(f'Gimbal pitch = {pitch}° (acceptable: [-10, 10]) (+10)')
            else:
                feedback.append(f'Gimbal pitch = {pitch}° (need approx 0°) (+0)')
        except (TypeError, ValueError):
            feedback.append('Could not read GimbalPitch (+0)')

    # --- Check 7: Takeoff command present (5 pts) ---
    # Takeoff is MAV_CMD_NAV_TAKEOFF (22)
    has_takeoff = _has_command(plan, 22)
    details['has_takeoff'] = has_takeoff
    if has_takeoff:
        score += 5
        feedback.append('Takeoff command found (+5)')
    else:
        feedback.append('Takeoff command missing (+0)')

    # --- Check 8: RTL command present (10 pts) ---
    # RTL is MAV_CMD_NAV_RETURN_TO_LAUNCH (20)
    has_rtl = _has_command(plan, 20)
    details['has_rtl'] = has_rtl
    if has_rtl:
        score += 10
        feedback.append('RTL command found (+10)')
    else:
        feedback.append('RTL command missing (+0)')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }