"""
Verifier for bart_rl_learning_model task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                                     (10 pts)
  2. sub-99999 excluded from model fitting                                    (20 pts)
  3. All 11 real participants have alpha values present                       (15 pts)
  4. Alpha values are in valid range [0.001, 0.999] for all participants      (20 pts)
  5. Group mean alpha in plausible range [0.01, 0.50]                         (15 pts)
  6. MSE values present and plausible (>0 for at least 8 participants)        (10 pts)
  7. Group statistics present (mean_alpha, sd_alpha, n_valid)                 (10 pts)

Pass threshold: 60 pts

Note: We do not verify exact alpha values since the delta-learning RL model
fitting is numerically complex and depends on implementation details (grid
search resolution, optimization method, etc.). We verify structural correctness,
exclusion of contaminated participant, and plausibility of fitted parameters.
"""

import json
import os
import tempfile

PASS_THRESHOLD = 60
CONTAMINATED_PARTICIPANT = 'sub-99999'
REAL_PARTICIPANTS = [
    'sub-10159', 'sub-10171', 'sub-10189', 'sub-10206', 'sub-10217',
    'sub-10225', 'sub-10235', 'sub-10249', 'sub-10280', 'sub-10292', 'sub-10304'
]
ALPHA_MIN = 0.001
ALPHA_MAX = 0.999
PLAUSIBLE_GROUP_MEAN_MIN = 0.01
PLAUSIBLE_GROUP_MEAN_MAX = 0.50


def _safe_float(val):
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


def _normalize_id(pid):
    import re
    pid = str(pid).strip()
    if re.match(r'^sub-\d+$', pid):
        return pid
    m = re.match(r'^sub(\d+)$', pid)
    if m:
        return f'sub-{m.group(1)}'
    return pid


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


def verify_bart_rl_learning_model(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Criterion 1: Output file exists and is valid JSON ---
    report = _read_json_from_env(copy_from_env, '/home/ga/pebl/analysis/bart_rl_report.json')
    if report is None:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/bart_rl_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    if report == 'invalid_json':
        feedback_parts.append('[0] Output file exists but is not valid JSON.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

    score += 10
    feedback_parts.append('[+10] Output file found and is valid JSON.')

    # Build participant lookup
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
        # If alpha is present but entry is for excluded participant, that's wrong
        alpha_val = _safe_float(cont_entry.get('alpha'))
        if alpha_val is None and not cont_entry.get('excluded'):
            excluded_ok = True
    else:
        # Not in report at all = excluded
        excl_list = report.get('excluded', [])
        if isinstance(excl_list, list) and any(_normalize_id(x) == cont_norm for x in excl_list):
            excluded_ok = True
        else:
            excluded_ok = True  # Not present = excluded

    if excluded_ok:
        score += 20
        feedback_parts.append('[+20] Contaminated participant sub-99999 correctly excluded.')
    else:
        feedback_parts.append(
            '[0] sub-99999 included with alpha value — must be excluded '
            '(ADJMEANPUMPS=0 makes RL model fitting meaningless for this participant).'
        )

    # --- Criterion 3: All 11 real participants have alpha present ---
    present_with_alpha = 0
    for pid in REAL_PARTICIPANTS:
        entry = part_map.get(_normalize_id(pid))
        if entry and not entry.get('excluded'):
            alpha_val = _safe_float(entry.get('alpha') or entry.get('learning_rate') or
                                    entry.get('alpha_estimate'))
            if alpha_val is not None:
                present_with_alpha += 1

    if present_with_alpha == 11:
        score += 15
        feedback_parts.append('[+15] All 11 real participants have alpha values.')
    elif present_with_alpha >= 7:
        partial = 8
        score += partial
        feedback_parts.append(f'[+{partial}] {present_with_alpha}/11 participants have alpha values (partial).')
    else:
        feedback_parts.append(f'[0] Only {present_with_alpha}/11 participants have alpha values.')

    # --- Criterion 4: Alpha values in valid range ---
    in_range_count = 0
    all_alphas = []
    for pid in REAL_PARTICIPANTS:
        entry = part_map.get(_normalize_id(pid))
        if not entry or entry.get('excluded'):
            continue
        alpha_val = _safe_float(entry.get('alpha') or entry.get('learning_rate') or
                                entry.get('alpha_estimate'))
        if alpha_val is not None:
            all_alphas.append(alpha_val)
            if ALPHA_MIN <= alpha_val <= ALPHA_MAX:
                in_range_count += 1

    if in_range_count >= 9:
        score += 20
        feedback_parts.append(f'[+20] {in_range_count}/11 alpha values in valid range [{ALPHA_MIN}, {ALPHA_MAX}].')
    elif in_range_count >= 5:
        partial = 10
        score += partial
        feedback_parts.append(f'[+{partial}] {in_range_count}/11 alpha values in valid range (partial).')
    else:
        feedback_parts.append(f'[0] Only {in_range_count}/11 alpha values in range [{ALPHA_MIN}, {ALPHA_MAX}].')

    # --- Criterion 5: Group mean alpha in plausible range ---
    group_stats = report.get('group_statistics', report.get('group_stats', {}))
    group_mean_alpha = None
    if isinstance(group_stats, dict):
        group_mean_alpha = _safe_float(
            group_stats.get('mean_alpha') or group_stats.get('alpha_mean') or
            group_stats.get('group_mean_alpha')
        )
    # Also compute from participant entries if not in group stats
    if group_mean_alpha is None and all_alphas:
        group_mean_alpha = sum(all_alphas) / len(all_alphas)

    if group_mean_alpha is not None:
        if PLAUSIBLE_GROUP_MEAN_MIN <= group_mean_alpha <= PLAUSIBLE_GROUP_MEAN_MAX:
            score += 15
            feedback_parts.append(
                f'[+15] Group mean alpha {group_mean_alpha:.4f} in plausible range '
                f'[{PLAUSIBLE_GROUP_MEAN_MIN}, {PLAUSIBLE_GROUP_MEAN_MAX}].'
            )
        else:
            feedback_parts.append(
                f'[0] Group mean alpha {group_mean_alpha:.4f} outside plausible range '
                f'[{PLAUSIBLE_GROUP_MEAN_MIN}, {PLAUSIBLE_GROUP_MEAN_MAX}].'
            )
    else:
        feedback_parts.append('[0] Could not determine group mean alpha.')

    # --- Criterion 6: MSE values present and plausible ---
    mse_count = 0
    for pid in REAL_PARTICIPANTS:
        entry = part_map.get(_normalize_id(pid))
        if not entry or entry.get('excluded'):
            continue
        mse_val = _safe_float(entry.get('mse') or entry.get('mean_squared_error') or
                              entry.get('fit_mse'))
        if mse_val is not None and mse_val > 0:
            mse_count += 1

    if mse_count >= 8:
        score += 10
        feedback_parts.append(f'[+10] MSE values present and >0 for {mse_count}/11 participants.')
    elif mse_count >= 4:
        partial = 5
        score += partial
        feedback_parts.append(f'[+{partial}] MSE values present for {mse_count}/11 participants (partial).')
    else:
        feedback_parts.append(f'[0] MSE values missing or zero for most participants ({mse_count}/11).')

    # --- Criterion 7: Group statistics present ---
    if isinstance(group_stats, dict):
        has_mean = any(k in group_stats for k in ['mean_alpha', 'alpha_mean', 'group_mean_alpha'])
        has_sd = any(k in group_stats for k in ['sd_alpha', 'alpha_sd', 'std_alpha', 'group_sd_alpha'])
        has_n = any(k in group_stats for k in ['n_valid', 'n', 'n_participants'])
        if has_mean and has_sd and has_n:
            score += 10
            feedback_parts.append('[+10] Group statistics (mean_alpha, sd_alpha, n_valid) all present.')
        elif has_mean:
            partial = 5
            score += partial
            feedback_parts.append(f'[+{partial}] Group statistics partially present (mean_alpha found, sd_alpha or n missing).')
        else:
            feedback_parts.append('[0] group_statistics key missing or incomplete.')
    else:
        feedback_parts.append('[0] group_statistics key not found in report.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
