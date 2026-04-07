"""
Verifier for sternberg_accuracy_speed_tradeoff task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant sub-99999 is excluded/flagged           (25 pts)
  3. Mean accuracy per set size correct for ≥8 valid ppts         (30 pts)
  4. Mean RT per set size correct for ≥8 valid ppts               (20 pts)
  5. Group means by set size correct (within tolerance)           (15 pts)

Pass threshold: 60 pts

Ground truth computed from: real CNP OpenNeuro ds000030 SCAP data.
Source: Gorgolewski et al. (2017). Scientific Data. doi:10.1038/sdata.2017.93
Set sizes: 1, 3, 5, 7 (number of spatial locations to remember)
sub-99999: 100% accuracy + RT=50-80ms (impossible for working memory task)

Max partial score check (Anti-Pattern 4):
  partial max = 15 (criteria 3+4 partial) = 7+8=15 < 60 threshold ✓
"""

import json
import os
import tempfile

CONTAMINATED_PARTICIPANT = 'sub-99999'
PASS_THRESHOLD = 60
ACC_TOLERANCE = 0.10   # ±10% accuracy
RT_TOLERANCE = 150.0   # ±150ms
GROUP_ACC_TOLERANCE = 0.07
GROUP_RT_TOLERANCE = 100.0
MIN_CORRECT_PPTS = 8

# Ground truth per participant, keyed by set_size
# Format: {participant_id: {set_size: {'mean_acc': float, 'mean_rt': float}}}
# Computed from real CNP ds000030 SCAP data
GROUND_TRUTH = {
    'sub10159': {1: {'mean_acc': 0.7500, 'mean_rt': 1088.2},  3: {'mean_acc': 0.5833, 'mean_rt': 1219.4},
                 5: {'mean_acc': 0.4167, 'mean_rt': 1472.5},  7: {'mean_acc': 0.6667, 'mean_rt': 1359.5}},
    'sub10171': {1: {'mean_acc': 0.9000, 'mean_rt': 760.1},   3: {'mean_acc': 0.9091, 'mean_rt': 1055.2},
                 5: {'mean_acc': 0.6000, 'mean_rt': 1219.8},  7: {'mean_acc': 0.7273, 'mean_rt': 1544.0}},
    'sub10189': {1: {'mean_acc': 0.9167, 'mean_rt': 869.4},   3: {'mean_acc': 1.0000, 'mean_rt': 940.0},
                 5: {'mean_acc': 0.8333, 'mean_rt': 976.9},   7: {'mean_acc': 0.7273, 'mean_rt': 1146.8}},
    'sub10206': {1: {'mean_acc': 0.9167, 'mean_rt': 781.4},   3: {'mean_acc': 0.6667, 'mean_rt': 1071.3},
                 5: {'mean_acc': 0.9167, 'mean_rt': 1038.9},  7: {'mean_acc': 0.7500, 'mean_rt': 947.6}},
    'sub10217': {1: {'mean_acc': 0.9167, 'mean_rt': 839.4},   3: {'mean_acc': 1.0000, 'mean_rt': 936.3},
                 5: {'mean_acc': 0.8333, 'mean_rt': 1114.0},  7: {'mean_acc': 0.8333, 'mean_rt': 1087.0}},
    'sub10225': {1: {'mean_acc': 0.8750, 'mean_rt': 1121.0},  3: {'mean_acc': 0.9000, 'mean_rt': 1013.9},
                 5: {'mean_acc': 1.0000, 'mean_rt': 1184.1},  7: {'mean_acc': 0.8333, 'mean_rt': 1076.5}},
    'sub10235': {1: {'mean_acc': 1.0000, 'mean_rt': 847.2},   3: {'mean_acc': 0.8333, 'mean_rt': 1073.1},
                 5: {'mean_acc': 0.8333, 'mean_rt': 1333.0},  7: {'mean_acc': 0.8333, 'mean_rt': 985.4}},
    'sub10249': {1: {'mean_acc': 0.9000, 'mean_rt': 1417.6},  3: {'mean_acc': 0.6000, 'mean_rt': 1649.2},
                 5: {'mean_acc': 0.7273, 'mean_rt': 1389.4},  7: {'mean_acc': 0.7273, 'mean_rt': 1629.1}},
    'sub10280': {1: {'mean_acc': 1.0000, 'mean_rt': 952.3},   3: {'mean_acc': 0.8182, 'mean_rt': 1089.6},
                 5: {'mean_acc': 0.7500, 'mean_rt': 1120.7},  7: {'mean_acc': 0.7500, 'mean_rt': 1206.6}},
    'sub10292': {1: {'mean_acc': 1.0000, 'mean_rt': 1213.8},  3: {'mean_acc': 0.9167, 'mean_rt': 1254.2},
                 5: {'mean_acc': 1.0000, 'mean_rt': 1423.2},  7: {'mean_acc': 0.8182, 'mean_rt': 1734.8}},
    'sub10304': {1: {'mean_acc': 1.0000, 'mean_rt': 899.2},   3: {'mean_acc': 1.0000, 'mean_rt': 1004.0},
                 5: {'mean_acc': 1.0000, 'mean_rt': 1042.9},  7: {'mean_acc': 0.7500, 'mean_rt': 1150.3}},
}
# Group means by set size (excluding sub-99999)
GROUP_MEANS_GT = {
    1: {'mean_acc': 0.9250, 'mean_rt': 980.9},
    3: {'mean_acc': 0.8388, 'mean_rt': 1118.7},
    5: {'mean_acc': 0.8101, 'mean_rt': 1210.5},
    7: {'mean_acc': 0.7652, 'mean_rt': 1260.7},
}


def _find_in_entry(entry, *keys, default=None):
    for k in keys:
        if k in entry:
            return entry[k]
    return default


def verify_sternberg_accuracy_speed_tradeoff(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # --- Criterion 1: Output file exists and is valid JSON ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/sternberg_analysis.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/sternberg_analysis.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # Build participant lookup
    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = (entry.get('id') or entry.get('participant_id') or entry.get('participant'))
        if pid:
            part_map[str(pid)] = entry

    # --- Criterion 2: Corrupted participant sub-99999 excluded ---
    sub99_entry = part_map.get(CONTAMINATED_PARTICIPANT)
    sub99_excluded = False
    if sub99_entry:
        if sub99_entry.get('excluded') in (True, 'true', 1, 'yes'):
            sub99_excluded = True
        elif sub99_entry.get('flagged') in (True, 'true', 1, 'yes'):
            sub99_excluded = True
    elif CONTAMINATED_PARTICIPANT not in part_map:
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and CONTAMINATED_PARTICIPANT in excluded_list:
            sub99_excluded = True

    if sub99_excluded:
        score += 25
        feedback_parts.append(f'[+25] Contaminated participant {CONTAMINATED_PARTICIPANT} correctly flagged/excluded.')
    else:
        feedback_parts.append(f'[0] Participant {CONTAMINATED_PARTICIPANT} not flagged despite impossible data (100% acc, RT<100ms).')

    # --- Criterion 3 & 4: Accuracy and RT per set size for ≥8 participants ---
    def get_set_size_stats(entry, ss):
        ss_str = str(ss)
        for key in ('set_sizes', 'results', 'by_set_size', 'set_size_data'):
            nested = entry.get(key)
            if isinstance(nested, dict):
                ss_data = nested.get(ss) or nested.get(ss_str)
                if ss_data:
                    return ss_data
            elif isinstance(nested, list):
                for item in nested:
                    if item.get('set_size') == ss or item.get('set_size') == ss_str:
                        return item
        return None

    correct_acc_ppts = 0
    correct_rt_ppts = 0
    for pid, gt in GROUND_TRUTH.items():
        entry = part_map.get(pid)
        if entry is None or entry.get('excluded') in (True, 'true', 1, 'yes'):
            continue
        acc_ok_count = 0
        rt_ok_count = 0
        for ss in (1, 3, 5, 7):
            ss_data = get_set_size_stats(entry, ss)
            if ss_data is None:
                continue
            gt_acc = gt[ss]['mean_acc']
            gt_rt = gt[ss]['mean_rt']
            acc = (ss_data.get('mean_acc') or ss_data.get('accuracy') or
                   ss_data.get('mean_accuracy') or ss_data.get('acc'))
            rt = (ss_data.get('mean_rt_ms') or ss_data.get('mean_rt') or
                  ss_data.get('response_time_ms') or ss_data.get('rt_ms'))
            if acc is not None:
                try:
                    if abs(float(acc) - gt_acc) <= ACC_TOLERANCE:
                        acc_ok_count += 1
                except (TypeError, ValueError):
                    pass
            if rt is not None:
                try:
                    if abs(float(rt) - gt_rt) <= RT_TOLERANCE:
                        rt_ok_count += 1
                except (TypeError, ValueError):
                    pass
        if acc_ok_count >= 3:
            correct_acc_ppts += 1
        if rt_ok_count >= 3:
            correct_rt_ppts += 1

    if correct_acc_ppts >= MIN_CORRECT_PPTS:
        score += 30
        feedback_parts.append(f'[+30] Accuracy correct for {correct_acc_ppts}/11 valid participants.')
    elif correct_acc_ppts >= 4:
        partial = 15
        score += partial
        feedback_parts.append(f'[+{partial}] Accuracy correct for {correct_acc_ppts}/11 participants (partial).')
    else:
        feedback_parts.append(f'[0] Accuracy correct for only {correct_acc_ppts}/11 participants.')

    if correct_rt_ppts >= MIN_CORRECT_PPTS:
        score += 20
        feedback_parts.append(f'[+20] RT correct for {correct_rt_ppts}/11 valid participants.')
    elif correct_rt_ppts >= 4:
        partial = 8
        score += partial
        feedback_parts.append(f'[+{partial}] RT correct for {correct_rt_ppts}/11 participants (partial).')
    else:
        feedback_parts.append(f'[0] RT correct for only {correct_rt_ppts}/11 participants.')

    # --- Criterion 5: Group means by set size ---
    group_means = (report.get('group_means') or report.get('group_mean') or
                   report.get('overall_means') or report.get('summary'))
    if isinstance(group_means, dict):
        correct_group = 0
        total_group = 0
        for ss in (1, 3, 5, 7):
            ss_str = str(ss)
            ss_data = group_means.get(ss) or group_means.get(ss_str)
            if ss_data is None:
                continue
            total_group += 1
            gt_acc = GROUP_MEANS_GT[ss]['mean_acc']
            gt_rt = GROUP_MEANS_GT[ss]['mean_rt']
            acc = (ss_data.get('mean_acc') or ss_data.get('accuracy') or ss_data.get('mean_accuracy'))
            rt = (ss_data.get('mean_rt_ms') or ss_data.get('mean_rt') or ss_data.get('rt_ms'))
            acc_ok = acc is not None and abs(float(acc) - gt_acc) <= GROUP_ACC_TOLERANCE
            rt_ok = rt is not None and abs(float(rt) - gt_rt) <= GROUP_RT_TOLERANCE
            if acc_ok and rt_ok:
                correct_group += 1
        if correct_group >= 3:
            score += 15
            feedback_parts.append(f'[+15] Group means correct for {correct_group}/4 set sizes.')
        elif correct_group >= 2:
            score += 7
            feedback_parts.append(f'[+7] Group means correct for {correct_group}/4 set sizes (partial).')
        else:
            feedback_parts.append(f'[0] Group means correct for only {correct_group}/4 set sizes.')
    else:
        feedback_parts.append('[0] "group_means" key missing or not a dict.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
