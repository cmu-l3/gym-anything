"""
Verifier for flanker_inhibitory_control_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                           (10 pts)
  2. Contaminated participant s99 is excluded                       (20 pts)
  3. All 27 real participants present in report                     (20 pts)
  4. Per-participant interference scores within ±15ms for ≥20 ppts (30 pts)
  5. Group mean interference score within ±8ms of ground truth     (20 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile

# Ground truth: per-participant interference scores (incongruent - congruent mean RT in ms)
# Computed from the real flanker_rt_data.csv (s1–s27, no contamination)
GROUND_TRUTH_SCORES_MS = {
    's1':  16.58,  's2':  80.02,  's3':  20.26,  's4':  26.91,
    's5':  67.82,  's6':  43.47,  's7':  22.64,  's8':  66.22,
    's9':   6.13,  's10': 27.82,  's11': 55.52,  's12': 77.00,
    's13': 59.33,  's14': 16.28,  's15': 43.04,  's16': 59.21,
    's17': 66.92,  's18': 38.28,  's19': 52.23,  's20': 44.33,
    's21': 89.48,  's22': 64.44,  's23':  4.60,  's24': 27.60,
    's25': 63.06,  's26': 37.02,  's27': 61.83,
}
GROUP_MEAN_GT_MS = 45.84  # ms
REAL_PARTICIPANTS = set(GROUND_TRUTH_SCORES_MS.keys())
CONTAMINATED_PARTICIPANT = 's99'
TOLERANCE_PER_PART_MS = 15.0
TOLERANCE_GROUP_MS = 8.0
MIN_CORRECT_PARTS = 20
PASS_THRESHOLD = 60


def verify_flanker_inhibitory_control_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Criterion 1: Output file exists and is valid JSON ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/flanker_report.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/flanker_report.json not found.')
        return {'passed': False, 'score': 0,
                'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file exists but is not valid JSON: {e}')
        return {'passed': False, 'score': 0,
                'feedback': ' '.join(feedback_parts)}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # Parse the participants list
    participants_list = report.get('participants', [])
    if not isinstance(participants_list, list):
        feedback_parts.append('[0] "participants" key missing or not a list.')
        return {'passed': False, 'score': score, 'feedback': ' '.join(feedback_parts)}

    # Build lookup: participant id -> entry
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    # --- Criterion 2: Contaminated participant s99 is excluded ---
    s99_entry = part_map.get(CONTAMINATED_PARTICIPANT)
    if s99_entry and s99_entry.get('excluded') in (True, 'true', 1, 'yes'):
        score += 20
        feedback_parts.append(f'[+20] Participant {CONTAMINATED_PARTICIPANT} correctly identified and excluded.')
    elif CONTAMINATED_PARTICIPANT not in part_map:
        # Not in the list at all — check if the report mentions exclusions separately
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and CONTAMINATED_PARTICIPANT in excluded_list:
            score += 20
            feedback_parts.append(f'[+20] Participant {CONTAMINATED_PARTICIPANT} correctly excluded (in exclusion list).')
        else:
            feedback_parts.append(f'[0] Contaminated participant {CONTAMINATED_PARTICIPANT} not excluded or not mentioned.')
    else:
        feedback_parts.append(f'[0] Participant {CONTAMINATED_PARTICIPANT} present but not marked as excluded.')

    # --- Criterion 3: All 27 real participants present ---
    present_real = REAL_PARTICIPANTS.intersection(part_map.keys())
    # Also check top-level "excluded" list for participants listed there
    top_excluded = report.get('excluded', [])
    if isinstance(top_excluded, list):
        present_real = present_real.union(REAL_PARTICIPANTS.intersection(top_excluded))
    if len(present_real) == 27:
        score += 20
        feedback_parts.append('[+20] All 27 real participants present in report.')
    elif len(present_real) >= 20:
        partial = 10
        score += partial
        feedback_parts.append(f'[+{partial}] {len(present_real)}/27 real participants present (partial credit).')
    else:
        feedback_parts.append(f'[0] Only {len(present_real)}/27 real participants present.')

    # --- Criterion 4: Per-participant interference scores within tolerance ---
    correct_scores = 0
    for pid, gt_ms in GROUND_TRUTH_SCORES_MS.items():
        entry = part_map.get(pid)
        if entry is None:
            continue
        if entry.get('excluded'):
            continue
        # Find interference score in the entry
        iscore = (entry.get('interference_score_ms') or
                  entry.get('interference_ms') or
                  entry.get('flanker_effect_ms') or
                  entry.get('interference_score') or
                  entry.get('effect_ms'))
        if iscore is None:
            # Try computing from mean RTs in the entry
            cong = entry.get('mean_rt_congruent_ms') or entry.get('mean_congruent_rt_ms') or entry.get('congruent_mean_ms')
            incong = entry.get('mean_rt_incongruent_ms') or entry.get('mean_incongruent_rt_ms') or entry.get('incongruent_mean_ms')
            if cong is not None and incong is not None:
                try:
                    iscore = float(incong) - float(cong)
                except (TypeError, ValueError):
                    pass
        if iscore is not None:
            try:
                diff = abs(float(iscore) - gt_ms)
                if diff <= TOLERANCE_PER_PART_MS:
                    correct_scores += 1
            except (TypeError, ValueError):
                pass

    if correct_scores >= MIN_CORRECT_PARTS:
        score += 30
        feedback_parts.append(f'[+30] {correct_scores}/27 interference scores within ±{TOLERANCE_PER_PART_MS}ms tolerance.')
    elif correct_scores >= 15:
        partial = 15
        score += partial
        feedback_parts.append(f'[+{partial}] {correct_scores}/27 interference scores within tolerance (partial).')
    else:
        feedback_parts.append(f'[0] Only {correct_scores}/27 interference scores within ±{TOLERANCE_PER_PART_MS}ms.')

    # --- Criterion 5: Group mean interference score ---
    group_mean = (report.get('group_mean_interference_ms') or
                  report.get('group_mean_interference') or
                  report.get('mean_interference_ms') or
                  report.get('overall_mean_interference_ms'))
    if group_mean is not None:
        try:
            diff = abs(float(group_mean) - GROUP_MEAN_GT_MS)
            if diff <= TOLERANCE_GROUP_MS:
                score += 20
                feedback_parts.append(f'[+20] Group mean interference {float(group_mean):.2f}ms within ±{TOLERANCE_GROUP_MS}ms of ground truth {GROUP_MEAN_GT_MS}ms.')
            else:
                feedback_parts.append(f'[0] Group mean {float(group_mean):.2f}ms differs from ground truth {GROUP_MEAN_GT_MS}ms by {diff:.2f}ms.')
        except (TypeError, ValueError):
            feedback_parts.append('[0] Group mean interference value could not be parsed.')
    else:
        feedback_parts.append('[0] "group_mean_interference_ms" key missing from report.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
