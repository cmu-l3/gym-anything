#!/usr/bin/env python3
"""Verifier for broken_mission_repair task.

The agent must fix a corrupted QGC mission plan:
  - items[1] alt was 5m → should be ~50m
  - items[3] alt was 5m → should be ~50m
  - items[4] alt was 350m → should be ~50m
  - RTL (cmd=20) was missing → must be added back

Scoring (100 pts total, pass = 70):
  10  Fixed file exists at /home/ga/Documents/QGC/fixed_mission.plan
  10  File modified during task
  15  items[1] altitude in [40, 60] m
  15  items[3] altitude in [40, 60] m
  15  items[4] altitude in [40, 60] m
  35  RTL command (cmd=20) present in mission
"""

import json
import os
import tempfile

ALT_LOW = 40.0
ALT_HIGH = 60.0
RTL_COMMAND = 20


def _get_item_altitude(item):
    """Extract altitude from a SimpleItem, trying Altitude and params[6]."""
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


def verify_broken_mission_repair(traj, env_info, task_info):
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

    # --- Check 1: Fixed file exists (10 pts) ---
    file_found = result.get('file_found', False)
    if file_found:
        score += 10
        feedback.append('Fixed mission file exists (+10)')
    else:
        feedback.append('Fixed mission file not found at expected path (+0)')
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
        feedback.append(f'Cannot parse fixed plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    details['item_count'] = len(items)

    # Build a list of all altitudes for debugging
    all_alts = [(_get_item_altitude(it), it.get('command')) for it in items]
    details['all_items_alt_cmd'] = [(a, c) for a, c in all_alts]

    # --- Checks 3, 4, 5: items[1], [3], [4] altitudes (15 pts each) ---
    # These are the indices in the broken file; after repair the indices should be same
    # (agent should keep same structure, just fix altitudes)
    nav_waypoints = [it for it in items if it.get('command') == 16]
    details['nav_waypoint_alts'] = [_get_item_altitude(w) for w in nav_waypoints]

    # Check waypoints at original broken indices (1, 3, 4)
    for idx, label, pts in [(1, 'items[1]', 15), (3, 'items[3]', 15), (4, 'items[4]', 15)]:
        if idx < len(items):
            alt = _get_item_altitude(items[idx])
            details[f'item_{idx}_alt'] = alt
            if alt is not None and ALT_LOW <= alt <= ALT_HIGH:
                score += pts
                feedback.append(f'{label} altitude={alt:.0f}m ✓ (+{pts})')
            elif alt is not None:
                feedback.append(f'{label} altitude={alt:.0f}m (need {ALT_LOW}-{ALT_HIGH}m) (+0)')
            else:
                feedback.append(f'{label} altitude could not be read (+0)')
        else:
            # Item may have been re-indexed; check nav waypoints instead
            if idx - 1 < len(nav_waypoints):
                alt = _get_item_altitude(nav_waypoints[idx - 1])
                if alt is not None and ALT_LOW <= alt <= ALT_HIGH:
                    score += pts
                    feedback.append(f'WP{idx} altitude={alt:.0f}m ✓ (+{pts})')
                else:
                    feedback.append(f'WP{idx} altitude={alt} (need {ALT_LOW}-{ALT_HIGH}m) (+0)')
            else:
                feedback.append(f'{label} not found in plan (+0)')

    # --- Check 6: RTL command present (35 pts) ---
    rtl_items = [it for it in items if it.get('command') == RTL_COMMAND]
    details['rtl_count'] = len(rtl_items)

    if rtl_items:
        score += 35
        # Bonus check: RTL should be the last item (or close to last)
        last_cmd = items[-1].get('command') if items else None
        if last_cmd == RTL_COMMAND:
            feedback.append('RTL command present at end of mission (+35)')
        else:
            feedback.append('RTL command present (not at end, but accepted) (+35)')
    else:
        feedback.append('RTL command (cmd=20) missing from mission (+0)')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }
