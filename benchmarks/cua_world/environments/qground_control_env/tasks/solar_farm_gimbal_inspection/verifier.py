#!/usr/bin/env python3
"""Verifier for solar_farm_gimbal_inspection task.

Checks that the agent:
1. Configured MNT1_TYPE = 2 (MAVLink gimbal).
2. Saved the plan file during the task.
3. Added >=3 NAV_WAYPOINT items.
4. Added >=3 DO_MOUNT_CONTROL items with pitch near -60.
5. Added >=3 NAV_LOITER_TIME items with time near 15 seconds.
6. Added >=3 DO_MOUNT_CONTROL items with pitch near 0.
7. Added an RTL command at the end.

Scoring (100 pts total, pass = 75):
  15  MNT1_TYPE == 2
  10  Plan file exists and was modified
  15  >=3 Waypoints created
  20  >=3 Inspection pitches (-60)
  20  >=3 Loiter times (15s)
  10  >=3 Transit pitches (0)
  10  RTL command present
"""

import json
import os
import tempfile


def has_param_near(item, val, tol=1.0):
    """Check if any numeric parameter in the item matches the target value."""
    for p in item.get('params', []):
        if p is not None:
            try:
                if abs(float(p) - val) <= tol:
                    return True
            except (TypeError, ValueError):
                pass
    return False


def verify_solar_farm_gimbal_inspection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Load result JSON
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

    # --- Check 1: MNT1_TYPE == 2 (15 pts) ---
    params = result.get('params', {})
    mnt1_type = params.get('MNT1_TYPE')
    details['MNT1_TYPE'] = mnt1_type

    if mnt1_type is not None and abs(float(mnt1_type) - 2.0) < 0.1:
        score += 15
        feedback.append('MNT1_TYPE set to 2 (MAVLink) ✓ (+15)')
    else:
        feedback.append(f'MNT1_TYPE is {mnt1_type} (expected 2.0) (+0/15)')

    # --- Check 2: Plan File Exists & Modified (10 pts) ---
    file_found = result.get('file_found', False)
    modified = result.get('modified_during_task', False)
    details['file_found'] = file_found
    details['modified'] = modified

    if file_found and modified:
        score += 10
        feedback.append('Plan file saved and modified during task ✓ (+10)')
    elif file_found:
        feedback.append('Plan file found but not modified during task (+0/10)')
        # Allow checking contents anyway to see if they got it right, but they fail the time check
    else:
        feedback.append('Plan file not found (+0/10)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # --- Parse the plan JSON ---
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
    
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e} (+0 for remaining mission checks)')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    details['total_items'] = len(items)

    # Count occurrences of specific commands
    waypoints = [it for it in items if it.get('command') == 16] # NAV_WAYPOINT
    loiters = [it for it in items if it.get('command') == 19] # NAV_LOITER_TIME
    mount_controls = [it for it in items if it.get('command') in (205, 1000)] # DO_MOUNT_CONTROL or PITCHYAW
    rtls = [it for it in items if it.get('command') == 20] # RTL

    details['waypoint_count'] = len(waypoints)
    details['loiter_count'] = len(loiters)
    details['mount_control_count'] = len(mount_controls)
    details['rtl_count'] = len(rtls)

    # --- Check 3: Waypoints (15 pts) ---
    if len(waypoints) >= 3:
        score += 15
        feedback.append(f'Found {len(waypoints)} Waypoints (need >=3) ✓ (+15)')
    else:
        feedback.append(f'Found {len(waypoints)} Waypoints (need >=3) (+0/15)')

    # --- Check 4: Inspection Pitch (20 pts) ---
    inspection_pitches = [it for it in mount_controls if has_param_near(it, -60.0)]
    details['inspection_pitch_count'] = len(inspection_pitches)
    if len(inspection_pitches) >= 3:
        score += 20
        feedback.append(f'Found {len(inspection_pitches)} Mount Controls at -60 deg (need >=3) ✓ (+20)')
    else:
        feedback.append(f'Found {len(inspection_pitches)} Mount Controls at -60 deg (need >=3) (+0/20)')

    # --- Check 5: Loiter Time (20 pts) ---
    # Loiter time is param 0 of command 19
    correct_loiters = [it for it in loiters if has_param_near(it, 15.0)]
    details['correct_loiter_count'] = len(correct_loiters)
    if len(correct_loiters) >= 3:
        score += 20
        feedback.append(f'Found {len(correct_loiters)} Loiters for 15s (need >=3) ✓ (+20)')
    else:
        feedback.append(f'Found {len(correct_loiters)} Loiters for 15s (need >=3) (+0/20)')

    # --- Check 6: Transit Pitch (10 pts) ---
    transit_pitches = [it for it in mount_controls if has_param_near(it, 0.0)]
    details['transit_pitch_count'] = len(transit_pitches)
    if len(transit_pitches) >= 3:
        score += 10
        feedback.append(f'Found {len(transit_pitches)} Mount Controls at 0 deg (need >=3) ✓ (+10)')
    else:
        feedback.append(f'Found {len(transit_pitches)} Mount Controls at 0 deg (need >=3) (+0/10)')

    # --- Check 7: Return Sequence (10 pts) ---
    if len(rtls) > 0:
        score += 10
        feedback.append('Found RTL command ✓ (+10)')
    else:
        feedback.append('No RTL command found (+0/10)')

    passed = score >= 75

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }