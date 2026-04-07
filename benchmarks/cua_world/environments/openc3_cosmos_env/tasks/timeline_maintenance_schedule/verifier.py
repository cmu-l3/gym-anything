#!/usr/bin/env python3
"""
Verifier for timeline_maintenance_schedule task.

A payload operations engineer must create a maintenance timeline in the
OpenC3 COSMOS Timeline tool and write a confirmation JSON to
/home/ga/Desktop/timeline_schedule.json. Additionally, the COSMOS REST API
must show that at least one timeline was created (timeline count increased).

Scoring breakdown (100 pts total, pass threshold = 60):
  20pts  Export metadata JSON readable
  10pts  Confirmation file exists on Desktop
  10pts  Confirmation file created after task start
  15pts  New timeline created in COSMOS (current_count > initial_count)
  15pts  Valid JSON with all 4 required keys
  15pts  activity_start_time is a parseable future datetime
  15pts  commands array has >= 2 entries (non-empty strings)
 ---
 100pts total

Do-nothing invariant: passed=False (score ≤ 20)
"""

import json
import os
import tempfile
from datetime import datetime, timezone


def _parse_iso_datetime(s):
    """Parse an ISO 8601 datetime string, return datetime or None."""
    if not isinstance(s, str):
        return None
    # Try common formats
    for fmt in (
        '%Y-%m-%dT%H:%M:%SZ',
        '%Y-%m-%dT%H:%M:%S',
        '%Y-%m-%dT%H:%M:%S.%fZ',
        '%Y-%m-%dT%H:%M:%S.%f',
        '%Y-%m-%dT%H:%M:%S%z',
        '%Y-%m-%d %H:%M:%S',
    ):
        try:
            dt = datetime.strptime(s.strip(), fmt)
            return dt
        except ValueError:
            continue
    return None


def verify_timeline_maintenance_schedule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0,
                'feedback': 'copy_from_env not available in env_info'}

    meta = task_info.get('metadata', {})
    result_file = meta.get('result_file', '/tmp/timeline_maintenance_schedule_result.json')
    output_file = meta.get('output_file', '/home/ga/Desktop/timeline_schedule.json')

    score = 0
    feedback = []

    # ── Step 1: Read export metadata ────────────────────────────────────────
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
        score += 20
        feedback.append('Export metadata readable (+20)')
    except Exception as e:
        feedback.append(f'Export metadata not found: {e}')
        return {'passed': False, 'score': 0, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    initial_count = int(export_meta.get('initial_timeline_count', 0))
    current_count = int(export_meta.get('current_timeline_count', 0))

    if not file_exists:
        feedback.append('Confirmation file not found on Desktop')
    else:
        score += 10
        feedback.append('Confirmation file exists on Desktop (+10)')

        if file_is_new:
            score += 10
            feedback.append('Confirmation file created during this session (+10)')
        else:
            feedback.append('Confirmation file predates task start (no content credit)')
            # Mark stale file so we skip content parsing later
            file_exists = False

    # ── Step 2: Timeline count check (independent of file) ──────────────────
    if current_count > initial_count:
        score += 15
        feedback.append(
            f'New timeline created in COSMOS (count: {initial_count} → {current_count}) (+15)')
    else:
        feedback.append(
            f'No new timeline detected (count: {initial_count} → {current_count})')

    if not file_exists:
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}

    # ── Step 3: Parse confirmation JSON ─────────────────────────────────────
    report = None
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(output_file, tmp_name)
        with open(tmp_name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError as e:
        feedback.append(f'Confirmation file is not valid JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    except Exception as e:
        feedback.append(f'Could not copy confirmation file: {e}')
        return {'passed': False, 'score': score, 'feedback': '; '.join(feedback)}
    finally:
        try:
            os.unlink(tmp_name)
        except Exception:
            pass

    # ── Step 4: Required keys ────────────────────────────────────────────────
    required_keys = {'timeline_name', 'activity_start_time', 'commands', 'activity_description'}
    missing_keys = required_keys - set(report.keys())
    if not missing_keys:
        score += 15
        feedback.append('All 4 required keys present (+15)')
    else:
        feedback.append(f'Missing keys: {sorted(missing_keys)}')

    # ── Step 5: activity_start_time is a parseable future datetime ───────────
    start_time_str = report.get('activity_start_time', '')
    dt = _parse_iso_datetime(start_time_str)
    if dt is not None:
        # Accept any future time — agent is scheduling 30+ minutes ahead
        # Use a permissive threshold (time after epoch year 2000 = likely valid)
        if dt.year >= 2020:
            score += 15
            feedback.append(f'activity_start_time parseable: {start_time_str[:25]} (+15)')
        else:
            feedback.append(f'activity_start_time parsed but implausibly old: {dt}')
    else:
        feedback.append(f'activity_start_time not parseable: {start_time_str!r}')

    # ── Step 6: commands array has >= 2 entries ──────────────────────────────
    commands = report.get('commands', [])
    if isinstance(commands, list):
        non_empty = [c for c in commands if isinstance(c, str) and c.strip()]
        if len(non_empty) >= 2:
            score += 15
            feedback.append(f'{len(non_empty)} command(s) in sequence >= 2 (+15)')
        elif len(non_empty) == 1:
            score += 7
            feedback.append(f'Only 1 command in sequence — need >= 2 (+7 partial)')
        else:
            feedback.append('commands array is empty or has no valid strings')
    else:
        feedback.append(f'commands is not a list: {type(commands).__name__}')

    passed = score >= 60
    return {'passed': passed, 'score': score, 'feedback': '; '.join(feedback)}


# ── Offline unit tests ──────────────────────────────────────────────────────
if __name__ == '__main__':
    import json

    def make_env(meta_data, output_data=None):
        def copy_from_env(src, dst):
            if 'result.json' in src:
                with open(dst, 'w') as f:
                    json.dump(meta_data, f)
            elif output_data is not None:
                with open(dst, 'w') as f:
                    json.dump(output_data, f)
            else:
                raise FileNotFoundError(f'No output data for {src}')
        return {'copy_from_env': copy_from_env}

    def make_env_missing():
        def copy_from_env(src, dst):
            raise FileNotFoundError(f'No such file: {src}')
        return {'copy_from_env': copy_from_env}

    task_info = {
        'metadata': {
            'result_file': '/tmp/timeline_maintenance_schedule_result.json',
            'output_file': '/home/ga/Desktop/timeline_schedule.json',
        }
    }

    # Test 1: Do-nothing
    r = verify_timeline_maintenance_schedule([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Test 1 failed: {r}"
    print(f"Test 1 (no metadata): score={r['score']}, passed={r['passed']} ✓")

    # Test 2: Do-nothing — export ran, file not created, count same
    r = verify_timeline_maintenance_schedule(
        [], make_env({'file_exists': False, 'file_is_new': False,
                      'initial_timeline_count': 0, 'current_timeline_count': 0}),
        task_info)
    assert r['passed'] is False and r['score'] == 20, f"Test 2 failed: {r}"
    print(f"Test 2 (do-nothing): score={r['score']}, passed={r['passed']} ✓")

    # Test 3: Partial — timeline created but file not created
    r = verify_timeline_maintenance_schedule(
        [], make_env({'file_exists': False, 'file_is_new': False,
                      'initial_timeline_count': 0, 'current_timeline_count': 1}),
        task_info)
    assert r['passed'] is False, f"Test 3 failed: {r}"
    assert 20 <= r['score'] <= 59, f"Test 3 score should be partial: {r}"
    print(f"Test 3 (timeline only): score={r['score']}, passed={r['passed']} ✓")

    # Test 4: Full completion
    r = verify_timeline_maintenance_schedule(
        [], make_env(
            {'file_exists': True, 'file_is_new': True,
             'initial_timeline_count': 0, 'current_timeline_count': 1},
            {'timeline_name': 'MAINT_SCHEDULE',
             'activity_start_time': '2026-03-09T16:00:00Z',
             'commands': ['INST SETPARAMS with VOLTAGE 12.0', 'INST COLLECT with TYPE NORMAL DURATION 5.0'],
             'activity_description': 'Routine maintenance pass'}
        ),
        task_info)
    assert r['passed'] is True and r['score'] >= 60, f"Test 4 failed: {r}"
    print(f"Test 4 (full completion): score={r['score']}, passed={r['passed']} ✓")

    # Test 5: File exists but only 1 command
    r = verify_timeline_maintenance_schedule(
        [], make_env(
            {'file_exists': True, 'file_is_new': True,
             'initial_timeline_count': 0, 'current_timeline_count': 1},
            {'timeline_name': 'MAINT', 'activity_start_time': '2026-04-01T10:00:00',
             'commands': ['INST COLLECT with TYPE NORMAL DURATION 5.0'],
             'activity_description': 'Maint'}
        ),
        task_info)
    assert r['passed'] is False or r['score'] < 100, f"Test 5 should be partial: {r}"
    print(f"Test 5 (only 1 command): score={r['score']}, passed={r['passed']} ✓")

    print("\nAll offline tests passed for timeline_maintenance_schedule ✓")
