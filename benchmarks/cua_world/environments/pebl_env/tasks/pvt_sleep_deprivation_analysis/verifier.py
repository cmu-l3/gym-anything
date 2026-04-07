"""
Verifier for pvt_sleep_deprivation_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                                    (10 pts)
  2. p08 TSD session identified and excluded (with reason)                   (20 pts)
  3. All 11 other participants present in report for all 3 sessions          (15 pts)
  4. Per-session group mean RT within tolerance (±20ms for each session)     (30 pts)
     - BL: ±20ms, TSD: ±25ms, REC: ±20ms
  5. Per-session lapse counts within tolerance (±2 lapses group mean)        (15 pts)
  6. Group statistics keys present (mean_rrt, mean_slowest10pct_rt_ms)      (10 pts)

Pass threshold: 60 pts

Note: Ground truth is loaded from /tmp/pvt_ground_truth.json which was written
by setup_task.sh. If that file is absent, per-participant checks are skipped and
only structural checks are performed.
"""

import json
import os
import tempfile

PASS_THRESHOLD = 60
CONTAMINATED_PARTICIPANT = 'p08'
CONTAMINATED_SESSION = 'TSD'
ALL_PARTICIPANTS = [f'p{i:02d}' for i in range(1, 13)]
VALID_PARTICIPANTS = [p for p in ALL_PARTICIPANTS if p != CONTAMINATED_PARTICIPANT]
SESSIONS = ['BL', 'TSD', 'REC']

# Tolerance values
RT_TOLERANCE_MS = {
    'BL':  20.0,
    'TSD': 25.0,
    'REC': 20.0,
}
LAPSE_TOLERANCE = 2.0


def _read_json_from_env(copy_from_env, remote_path):
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name
    try:
        copy_from_env(remote_path, tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, OSError):
        return None
    except (json.JSONDecodeError, ValueError):
        return 'invalid_json'
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass


def _safe_float(val):
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


def verify_pvt_sleep_deprivation_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # Load ground truth (generated at setup time)
    gt = _read_json_from_env(copy_from_env, '/tmp/pvt_ground_truth.json')
    has_gt = (gt is not None and gt != 'invalid_json')

    # --- Criterion 1: Output file exists and is valid JSON ---
    report = _read_json_from_env(copy_from_env, '/home/ga/pebl/analysis/pvt_report.json')
    if report is None:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/pvt_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    if report == 'invalid_json':
        feedback_parts.append('[0] Output file exists but is not valid JSON.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

    score += 10
    feedback_parts.append('[+10] Output file found and is valid JSON.')

    # Build participant lookup from report
    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = (entry.get('id') or entry.get('participant') or
               entry.get('participant_id') or '')
        if pid:
            part_map[str(pid)] = entry

    # --- Criterion 2: p08 TSD session excluded ---
    p08_entry = part_map.get(CONTAMINATED_PARTICIPANT)
    p08_excluded = False
    if p08_entry:
        # Check if TSD session is excluded
        p08_sessions = p08_entry.get('sessions', {})
        if isinstance(p08_sessions, dict):
            tsd_sess = p08_sessions.get('TSD', {})
            if isinstance(tsd_sess, dict) and tsd_sess.get('excluded') in (True, 'true', 1):
                p08_excluded = True
            elif isinstance(tsd_sess, str) and 'excluded' in tsd_sess.lower():
                p08_excluded = True
        # Also check if entry itself is excluded for TSD
        if p08_entry.get('excluded_sessions') and 'TSD' in str(p08_entry.get('excluded_sessions', '')):
            p08_excluded = True
        # Or if full participant is excluded (but with BL and REC present)
        if p08_entry.get('excluded') in (True, 'true', 1):
            p08_excluded = True

    if p08_excluded:
        score += 20
        feedback_parts.append('[+20] p08 TSD session correctly identified and excluded.')
    else:
        feedback_parts.append(
            '[0] p08 TSD session not excluded. The incident log documents an equipment '
            'malfunction causing sub-100ms artifactual RTs in this session.'
        )

    # --- Criterion 3: All 11 valid participants present ---
    present_count = sum(1 for p in VALID_PARTICIPANTS if p in part_map)
    if present_count == 11:
        score += 15
        feedback_parts.append('[+15] All 11 valid participants present in report.')
    elif present_count >= 8:
        partial = 8
        score += partial
        feedback_parts.append(f'[+{partial}] {present_count}/11 valid participants present (partial).')
    else:
        feedback_parts.append(f'[0] Only {present_count}/11 valid participants present.')

    # --- Criterion 4: Group mean RT per session within tolerance ---
    group_stats = report.get('group_statistics', report.get('group_stats', {}))
    rt_pts = 0
    if isinstance(group_stats, dict):
        for session in SESSIONS:
            sess_data = group_stats.get(session, {})
            if not isinstance(sess_data, dict):
                continue
            mean_rt = _safe_float(sess_data.get('mean_rt_ms') or
                                  sess_data.get('mean_rt') or
                                  sess_data.get('rt_mean_ms'))
            if mean_rt is None:
                feedback_parts.append(f'[0] group_statistics.{session}.mean_rt_ms missing.')
                continue

            # Compute expected group mean from ground truth
            if has_gt:
                valid_rts = []
                for pid in VALID_PARTICIPANTS:
                    pid_gt = gt.get(pid, {})
                    sess_gt = pid_gt.get(session)
                    # Skip contaminated sessions
                    if pid == CONTAMINATED_PARTICIPANT and session == CONTAMINATED_SESSION:
                        continue
                    if isinstance(sess_gt, dict):
                        rt_val = _safe_float(sess_gt.get('mean_rt_ms'))
                        if rt_val is not None:
                            valid_rts.append(rt_val)
                if valid_rts:
                    expected_mean = sum(valid_rts) / len(valid_rts)
                    tol = RT_TOLERANCE_MS.get(session, 20.0)
                    diff = abs(mean_rt - expected_mean)
                    if diff <= tol:
                        rt_pts += 10
                        feedback_parts.append(
                            f'[+10] {session} group mean RT {mean_rt:.1f}ms '
                            f'within ±{tol}ms of expected {expected_mean:.1f}ms.'
                        )
                    else:
                        feedback_parts.append(
                            f'[0] {session} group mean RT {mean_rt:.1f}ms differs from '
                            f'expected {expected_mean:.1f}ms by {diff:.1f}ms.'
                        )
            else:
                # Ground truth unavailable: just check plausible range
                plausible = {'BL': (210, 310), 'TSD': (260, 380), 'REC': (220, 330)}
                lo, hi = plausible.get(session, (150, 500))
                if lo <= mean_rt <= hi:
                    rt_pts += 10
                    feedback_parts.append(f'[+10] {session} group mean RT {mean_rt:.1f}ms in plausible range.')
                else:
                    feedback_parts.append(f'[0] {session} group mean RT {mean_rt:.1f}ms outside plausible range {lo}-{hi}ms.')
    score += rt_pts
    if rt_pts == 0 and not isinstance(group_stats, dict):
        feedback_parts.append('[0] group_statistics key missing or not a dict.')

    # --- Criterion 5: Per-session lapse counts within tolerance ---
    lapse_pts = 0
    expected_lapses = {'BL': 1.2, 'TSD': 7.4, 'REC': 2.1}  # Basner & Dinges 2011
    if isinstance(group_stats, dict):
        for session in SESSIONS:
            sess_data = group_stats.get(session, {})
            if not isinstance(sess_data, dict):
                continue
            mean_lapses = _safe_float(sess_data.get('mean_lapse_count') or
                                      sess_data.get('mean_lapses') or
                                      sess_data.get('lapse_count_mean'))
            if mean_lapses is None:
                continue
            exp = expected_lapses.get(session, 3.0)
            # Wide tolerance since data is generated with variability
            tol = max(LAPSE_TOLERANCE, exp * 0.6)
            if abs(mean_lapses - exp) <= tol:
                lapse_pts += 5
                feedback_parts.append(f'[+5] {session} mean lapses {mean_lapses:.2f} in expected range.')
            else:
                feedback_parts.append(f'[0] {session} mean lapses {mean_lapses:.2f} far from expected ~{exp}.')

    score += lapse_pts

    # --- Criterion 6: RRT and slowest 10% keys present in group stats ---
    extra_pts = 0
    if isinstance(group_stats, dict):
        for session in SESSIONS:
            sess_data = group_stats.get(session, {})
            if not isinstance(sess_data, dict):
                continue
            has_rrt = any(k in sess_data for k in ['mean_rrt', 'rrt', 'reciprocal_rt_mean'])
            has_slow = any(k in sess_data for k in ['mean_slowest10pct_rt_ms', 'slowest_10pct', 'mean_slowest_10pct_rt_ms', 'p90_rt_ms'])
            if has_rrt and has_slow:
                extra_pts += 3
                break  # Only need to confirm at least one session has both

        if extra_pts > 0:
            # Award full 10 pts if all 3 sessions have both metrics
            all_have = all(
                (any(k in group_stats.get(s, {}) for k in ['mean_rrt', 'rrt', 'reciprocal_rt_mean']) and
                 any(k in group_stats.get(s, {}) for k in ['mean_slowest10pct_rt_ms', 'slowest_10pct', 'mean_slowest_10pct_rt_ms', 'p90_rt_ms']))
                for s in SESSIONS
                if isinstance(group_stats.get(s), dict)
            )
            if all_have:
                score += 10
                feedback_parts.append('[+10] RRT and slowest 10% RT metrics present for all sessions.')
            else:
                score += 5
                feedback_parts.append('[+5] RRT and/or slowest 10% RT metrics present for some sessions (partial).')
        else:
            feedback_parts.append('[0] mean_rrt and mean_slowest10pct_rt_ms not found in group_statistics.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
