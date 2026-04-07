"""
Verifier for nback_dprime_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON (10 pts)
  2. Button-masher (s99) is excluded based on FAR > 0.80 (20 pts)
  3. Edge-case extreme value corrections applied correctly for perfect Hit/FA rates (20 pts)
  4. Individual participant d' metrics within ±0.05 tolerance of ground truth (30 pts)
  5. Group mean d' per level within ±0.05 tolerance of ground truth (20 pts)

Pass threshold: 70 pts
"""

import json
import os
import csv
import tempfile
from scipy.stats import norm

PASS_THRESHOLD = 70
TOLERANCE_INDIVIDUAL = 0.05
TOLERANCE_GROUP = 0.05
CONTAMINATED_PARTICIPANT = 's99'
EDGE_CASE_PARTICIPANTS = ['s01', 's02']


def calculate_ground_truth(csv_path):
    """Dynamically calculates ground truth from the deterministic CSV."""
    raw_data = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_data.append(row)
            
    # Structure: stats[subject_id][level] = {'targets': 0, 'lures': 0, 'hits': 0, 'false_alarms': 0}
    stats = {}
    overall_far_stats = {}  # stats[subject_id] = {'lures': 0, 'false_alarms': 0}
    
    for row in raw_data:
        subj = row['subject_id']
        level = row['nback_level']
        is_target = int(row['is_target'])
        resp = int(row['response'])
        
        if subj not in stats:
            stats[subj] = {'1': {'t':0, 'l':0, 'h':0, 'fa':0}, 
                           '2': {'t':0, 'l':0, 'h':0, 'fa':0}, 
                           '3': {'t':0, 'l':0, 'h':0, 'fa':0}}
            overall_far_stats[subj] = {'l': 0, 'fa': 0}
            
        if is_target == 1:
            stats[subj][level]['t'] += 1
            if resp == 1:
                stats[subj][level]['h'] += 1
        else:
            stats[subj][level]['l'] += 1
            overall_far_stats[subj]['l'] += 1
            if resp == 1:
                stats[subj][level]['fa'] += 1
                overall_far_stats[subj]['fa'] += 1

    gt = {
        'participants': {},
        'excluded': set(),
        'group_means': {'1back': 0.0, '2back': 0.0, '3back': 0.0}
    }
    
    valid_dprimes = {'1back': [], '2back': [], '3back': []}
    
    for subj in stats:
        # Check exclusion
        far_overall = overall_far_stats[subj]['fa'] / float(overall_far_stats[subj]['l'])
        if far_overall > 0.80:
            gt['excluded'].add(subj)
            continue
            
        gt['participants'][subj] = {}
        
        for level_num, level_key in [('1', '1back'), ('2', '2back'), ('3', '3back')]:
            t = float(stats[subj][level_num]['t'])
            l = float(stats[subj][level_num]['l'])
            h = float(stats[subj][level_num]['h'])
            fa = float(stats[subj][level_num]['fa'])
            
            hr = h / t if t > 0 else 0
            far = fa / l if l > 0 else 0
            
            # Log-linear extreme value corrections
            if hr == 1.0: hr = 19.5 / 20.0
            if hr == 0.0: hr = 0.5 / 20.0
            if far == 1.0: far = 39.5 / 40.0
            if far == 0.0: far = 0.5 / 40.0
            
            dprime = norm.ppf(hr) - norm.ppf(far)
            gt['participants'][subj][f'dprime_{level_key}'] = dprime
            valid_dprimes[level_key].append(dprime)

    # Calculate group means
    for k in valid_dprimes:
        if valid_dprimes[k]:
            gt['group_means'][k] = sum(valid_dprimes[k]) / len(valid_dprimes[k])

    return gt


def verify_nback_dprime_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # Get data paths
    data_path = '/home/ga/pebl/data/nback_data.csv'
    report_path = '/home/ga/pebl/analysis/nback_report.json'

    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv, \
         tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json:
        csv_local = tmp_csv.name
        json_local = tmp_json.name

    try:
        # Download files
        try:
            copy_from_env(data_path, csv_local)
        except Exception:
            return {'passed': False, 'score': 0, 'feedback': "Original dataset was missing/deleted from environment."}

        try:
            copy_from_env(report_path, json_local)
        except FileNotFoundError:
            feedback_parts.append('[0] Output file nback_report.json not found.')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

        # Load JSON
        try:
            with open(json_local, encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append('[+10] Output JSON valid.')
        except (json.JSONDecodeError, ValueError) as e:
            feedback_parts.append(f'[0] Output file is not valid JSON: {e}')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
            
        # Calculate dynamic Ground Truth
        gt = calculate_ground_truth(csv_local)

    finally:
        for p in [csv_local, json_local]:
            try:
                os.unlink(p)
            except Exception:
                pass

    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('subject_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        return False

    # --- Criterion 2: Button-masher (s99) excluded (20 pts) ---
    if is_excluded(CONTAMINATED_PARTICIPANT):
        score += 20
        feedback_parts.append(f'[+20] Participant {CONTAMINATED_PARTICIPANT} correctly excluded.')
    else:
        feedback_parts.append(f'[0] Participant {CONTAMINATED_PARTICIPANT} was NOT excluded despite FAR > 0.80.')

    # --- Criterion 3 & 4: Edge Cases & Individual Metrics (20 pts + 30 pts) ---
    correct_individuals = 0
    total_valid_ppts = len(gt['participants'])
    edge_cases_correct = 0

    for pid, gt_metrics in gt['participants'].items():
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
            
        pid_correct = True
        for level in ['dprime_1back', 'dprime_2back', 'dprime_3back']:
            val = entry.get(level)
            gt_val = gt_metrics[level]
            if val is None:
                pid_correct = False
                break
            try:
                if abs(float(val) - gt_val) > TOLERANCE_INDIVIDUAL:
                    pid_correct = False
                    break
            except (TypeError, ValueError):
                pid_correct = False
                break
                
        if pid_correct:
            correct_individuals += 1
            if pid in EDGE_CASE_PARTICIPANTS:
                edge_cases_correct += 1

    # Score Edge Cases
    if edge_cases_correct == len(EDGE_CASE_PARTICIPANTS):
        score += 20
        feedback_parts.append('[+20] Extreme value corrections (log-linear) applied correctly to perfect Hit/FA rates.')
    elif edge_cases_correct > 0:
        score += 10
        feedback_parts.append('[+10] Extreme value corrections applied partially.')
    else:
        feedback_parts.append('[0] Failed extreme value corrections (s01/s02 dprime calculations incorrect).')

    # Score Individual Metrics
    if correct_individuals >= total_valid_ppts - 2:
        score += 30
        feedback_parts.append(f'[+30] Individual d\' metrics highly accurate ({correct_individuals}/{total_valid_ppts}).')
    elif correct_individuals >= total_valid_ppts // 2:
        score += 15
        feedback_parts.append(f'[+15] Individual d\' metrics partially correct ({correct_individuals}/{total_valid_ppts}).')
    else:
        feedback_parts.append(f'[0] Individual d\' metrics mostly incorrect ({correct_individuals}/{total_valid_ppts}).')

    # --- Criterion 5: Group Means (20 pts) ---
    agent_group = report.get('group_mean_dprime', {})
    group_correct = 0
    
    for level_key in ['1back', '2back', '3back']:
        agent_val = agent_group.get(level_key)
        gt_val = gt['group_means'][level_key]
        
        if agent_val is not None:
            try:
                if abs(float(agent_val) - gt_val) <= TOLERANCE_GROUP:
                    group_correct += 1
            except (TypeError, ValueError):
                pass

    if group_correct == 3:
        score += 20
        feedback_parts.append('[+20] All group mean d\' values correct.')
    elif group_correct > 0:
        score += 10
        feedback_parts.append(f'[+10] {group_correct}/3 group mean d\' values correct.')
    else:
        feedback_parts.append('[0] Group mean d\' values incorrect or missing.')

    passed = score >= PASS_THRESHOLD
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }