"""
Verifier for cnp_multi_task_battery_report task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                               (10 pts)
  2. sub-99999 excluded from BART and/or Stop Signal analyses           (20 pts)
  3. All 11 real participants present in report                         (15 pts)
  4. ADJMEANPUMPS values within ±1.5 pumps of ground truth (≥8/11)     (20 pts)
  5. SSRT values within ±25ms of ground truth (≥8/11)                  (20 pts)
  6. SCAP SS7 accuracy values within ±10% of ground truth (≥8/11)      (10 pts)
  7. Z-scores present for at least 2 of 3 domains                      (5 pts)

Pass threshold: 60 pts

Ground truth (computed from real CNP assets):
  BART ADJMEANPUMPS (mean pumps on non-exploded trials):
    sub-10159: 3.15, sub-10171: 5.83, sub-10189: 5.50, sub-10206: 5.12,
    sub-10217: 4.80, sub-10225: 4.25, sub-10235: 2.50, sub-10249: 3.25,
    sub-10280: 3.92, sub-10292: 6.83, sub-10304: 3.12

  SSRT (ms) from stop-signal race model:
    sub-10159: 192.9, sub-10171: 188.5, sub-10189: 332.3, sub-10206: 243.3,
    sub-10217: 250.8, sub-10225: 242.7, sub-10235: 301.3, sub-10249: 346.6,
    sub-10280: 221.3, sub-10292: 224.5, sub-10304: 176.9

  SCAP SS7 accuracy (%):
    sub-10159: 66.7, sub-10171: 72.7, sub-10189: 72.7, sub-10206: 75.0,
    sub-10217: 83.3, sub-10225: 83.3, sub-10235: 83.3, sub-10249: 72.7,
    sub-10280: 75.0, sub-10292: 81.8, sub-10304: 75.0
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 60
CONTAMINATED_PARTICIPANT = 'sub-99999'

REAL_PARTICIPANTS = [
    'sub-10159', 'sub-10171', 'sub-10189', 'sub-10206', 'sub-10217',
    'sub-10225', 'sub-10235', 'sub-10249', 'sub-10280', 'sub-10292', 'sub-10304'
]

GT_ADJMEANPUMPS = {
    'sub-10159': 3.15, 'sub-10171': 5.83, 'sub-10189': 5.50, 'sub-10206': 5.12,
    'sub-10217': 4.80, 'sub-10225': 4.25, 'sub-10235': 2.50, 'sub-10249': 3.25,
    'sub-10280': 3.92, 'sub-10292': 6.83, 'sub-10304': 3.12,
}

GT_SSRT_MS = {
    'sub-10159': 192.9, 'sub-10171': 188.5, 'sub-10189': 332.3, 'sub-10206': 243.3,
    'sub-10217': 250.8, 'sub-10225': 242.7, 'sub-10235': 301.3, 'sub-10249': 346.6,
    'sub-10280': 221.3, 'sub-10292': 224.5, 'sub-10304': 176.9,
}

GT_SCAP_SS7 = {
    'sub-10159': 66.7, 'sub-10171': 72.7, 'sub-10189': 72.7, 'sub-10206': 75.0,
    'sub-10217': 83.3, 'sub-10225': 83.3, 'sub-10235': 83.3, 'sub-10249': 72.7,
    'sub-10280': 75.0, 'sub-10292': 81.8, 'sub-10304': 75.0,
}

ADJMEANPUMPS_TOL = 1.5    # pumps
SSRT_TOL = 25.0            # ms
SCAP_TOL = 10.0            # percentage points
MIN_CORRECT = 8            # out of 11


def _normalize_id(pid):
    """Normalize participant ID to 'sub-NNNNN' format."""
    pid = str(pid).strip()
    # Already correct format
    if re.match(r'^sub-\d+$', pid):
        return pid
    # Missing hyphen: sub10159 -> sub-10159
    m = re.match(r'^sub(\d+)$', pid)
    if m:
        return f'sub-{m.group(1)}'
    return pid


def _safe_float(val):
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


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


def verify_cnp_multi_task_battery_report(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Criterion 1: Output file exists and is valid JSON ---
    report = _read_json_from_env(copy_from_env, '/home/ga/pebl/analysis/cnp_battery_report.json')
    if report is None:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/cnp_battery_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    if report == 'invalid_json':
        feedback_parts.append('[0] Output file exists but is not valid JSON.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

    score += 10
    feedback_parts.append('[+10] Output file found and is valid JSON.')

    # Build participant lookup (normalize all IDs)
    participants_list = report.get('participants', [])
    if not isinstance(participants_list, list):
        feedback_parts.append('[0] "participants" key missing or not a list.')
        return {'passed': False, 'score': score, 'feedback': ' '.join(feedback_parts)}

    part_map = {}
    for entry in participants_list:
        raw_id = (entry.get('id') or entry.get('participant_id') or
                  entry.get('participant') or '')
        nid = _normalize_id(raw_id)
        if nid:
            part_map[nid] = entry

    # --- Criterion 2: sub-99999 excluded ---
    cont_norm = _normalize_id(CONTAMINATED_PARTICIPANT)
    cont_entry = part_map.get(cont_norm)
    excluded_ok = False
    if cont_entry:
        if cont_entry.get('excluded') in (True, 'true', 1, 'yes'):
            excluded_ok = True
        bart_field = cont_entry.get('bart_adjmeanpumps') or cont_entry.get('adjmeanpumps')
        ssrt_field = cont_entry.get('ssrt_ms') or cont_entry.get('ssrt')
        if bart_field is None and ssrt_field is None:
            excluded_ok = True
    else:
        # Not present at all — check excluded list
        excl_list = report.get('excluded', [])
        if isinstance(excl_list, list) and any(_normalize_id(x) == cont_norm for x in excl_list):
            excluded_ok = True
        elif cont_norm not in part_map:
            # Not in report at all counts as excluded
            excluded_ok = True

    if excluded_ok:
        score += 20
        feedback_parts.append('[+20] Contaminated participant sub-99999 correctly excluded.')
    else:
        feedback_parts.append(
            '[0] sub-99999 not excluded. This participant has ADJMEANPUMPS=0 '
            '(all balloons exploded with zero pumps — non-responsive pattern).'
        )

    # --- Criterion 3: All 11 real participants present ---
    present = sum(1 for p in REAL_PARTICIPANTS if _normalize_id(p) in part_map)
    if present == 11:
        score += 15
        feedback_parts.append('[+15] All 11 real participants present in report.')
    elif present >= 7:
        partial = 8
        score += partial
        feedback_parts.append(f'[+{partial}] {present}/11 real participants present (partial credit).')
    else:
        feedback_parts.append(f'[0] Only {present}/11 real participants present.')

    # --- Criterion 4: ADJMEANPUMPS within tolerance ---
    pumps_correct = 0
    for pid in REAL_PARTICIPANTS:
        entry = part_map.get(_normalize_id(pid))
        if not entry or entry.get('excluded'):
            continue
        val = _safe_float(entry.get('bart_adjmeanpumps') or entry.get('adjmeanpumps') or
                          entry.get('bart_adj_mean_pumps'))
        if val is not None:
            gt_val = GT_ADJMEANPUMPS.get(pid)
            if gt_val is not None and abs(val - gt_val) <= ADJMEANPUMPS_TOL:
                pumps_correct += 1

    if pumps_correct >= MIN_CORRECT:
        score += 20
        feedback_parts.append(f'[+20] {pumps_correct}/11 ADJMEANPUMPS values within ±{ADJMEANPUMPS_TOL} pumps of ground truth.')
    elif pumps_correct >= 5:
        partial = 10
        score += partial
        feedback_parts.append(f'[+{partial}] {pumps_correct}/11 ADJMEANPUMPS values within tolerance (partial).')
    else:
        feedback_parts.append(f'[0] Only {pumps_correct}/11 ADJMEANPUMPS values within ±{ADJMEANPUMPS_TOL} pumps.')

    # --- Criterion 5: SSRT within tolerance ---
    ssrt_correct = 0
    for pid in REAL_PARTICIPANTS:
        entry = part_map.get(_normalize_id(pid))
        if not entry or entry.get('excluded'):
            continue
        val = _safe_float(entry.get('ssrt_ms') or entry.get('ssrt') or
                          entry.get('stop_signal_rt_ms') or entry.get('ssrt_ms'))
        if val is not None:
            gt_val = GT_SSRT_MS.get(pid)
            if gt_val is not None and abs(val - gt_val) <= SSRT_TOL:
                ssrt_correct += 1

    if ssrt_correct >= MIN_CORRECT:
        score += 20
        feedback_parts.append(f'[+20] {ssrt_correct}/11 SSRT values within ±{SSRT_TOL}ms of ground truth.')
    elif ssrt_correct >= 5:
        partial = 10
        score += partial
        feedback_parts.append(f'[+{partial}] {ssrt_correct}/11 SSRT values within tolerance (partial).')
    else:
        feedback_parts.append(f'[0] Only {ssrt_correct}/11 SSRT values within ±{SSRT_TOL}ms.')

    # --- Criterion 6: SCAP SS7 accuracy within tolerance ---
    scap_correct = 0
    for pid in REAL_PARTICIPANTS:
        entry = part_map.get(_normalize_id(pid))
        if not entry:
            continue
        val = _safe_float(entry.get('scap_ss7_accuracy') or entry.get('scap_accuracy_ss7') or
                          entry.get('scap_wm_accuracy') or entry.get('scap_setsize7_accuracy'))
        if val is not None:
            # Accept both proportion (0-1) and percentage (0-100)
            if 0 < val <= 1.0:
                val = val * 100  # Convert to percentage
            gt_val = GT_SCAP_SS7.get(pid)
            if gt_val is not None and abs(val - gt_val) <= SCAP_TOL:
                scap_correct += 1

    if scap_correct >= MIN_CORRECT:
        score += 10
        feedback_parts.append(f'[+10] {scap_correct}/11 SCAP SS7 accuracy values within ±{SCAP_TOL}% of ground truth.')
    elif scap_correct >= 5:
        partial = 5
        score += partial
        feedback_parts.append(f'[+{partial}] {scap_correct}/11 SCAP SS7 accuracy values within tolerance (partial).')
    else:
        feedback_parts.append(f'[0] Only {scap_correct}/11 SCAP SS7 accuracy values within ±{SCAP_TOL}%.')

    # --- Criterion 7: Z-scores present ---
    z_count = 0
    for pid in REAL_PARTICIPANTS[:3]:  # Check a sample of participants
        entry = part_map.get(_normalize_id(pid))
        if not entry:
            continue
        has_z = any(entry.get(k) is not None for k in ['bart_z', 'ssrt_z', 'scap_z',
                                                         'bart_zscore', 'ssrt_zscore', 'scap_zscore'])
        if has_z:
            z_count += 1

    if z_count >= 2:
        score += 5
        feedback_parts.append('[+5] Z-scores present for domain measurements.')
    else:
        feedback_parts.append('[0] Z-scores not found in participant entries (bart_z, ssrt_z, scap_z).')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
