#!/usr/bin/env python3
"""
Verifier for swm_heuristic_strategy_analysis task.

Dynamically reconstructs ground truth directly from the agent's input data file,
then compares against the agent's output JSON report.

Scoring (100 pts total):
  1. Output file exists and is structurally valid JSON             (10 pts)
  2. Contaminated participant (sub-99) correctly excluded          (20 pts)
  3. total_wse correctly calculated for ≥ 12 valid participants    (20 pts)
  4. total_bse correctly calculated for ≥ 12 valid participants    (20 pts)
  5. strategy_score correctly calculated for ≥ 12 valid ppts       (15 pts)
  6. Group means are correct within ±0.5 tolerance                 (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import csv
import tempfile
import statistics

PASS_THRESHOLD = 60

def compute_ground_truth(csv_path):
    """Computes the exact SWM metrics by processing the raw click log."""
    gt_stats = {}
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        
        curr_pid = None
        curr_trial = None
        curr_search = None
        
        boxes_with_tokens = set()
        boxes_clicked_this_search = set()
        
        for row in reader:
            pid = row['participant_id']
            trial = int(row['trial'])
            bcount = int(row['boxes_count'])
            search = int(row['search_number'])
            click_seq = int(row['click_sequence'])
            box = int(row['box_clicked'])
            found = int(row['found_token'])
            
            if pid not in gt_stats:
                gt_stats[pid] = {'total_bse': 0, 'total_wse': 0, 'strategy_score': 0, 'trials_strat': {}}
                
            if trial != curr_trial or pid != curr_pid:
                boxes_with_tokens = set()
                curr_trial = trial
                curr_pid = pid
                
            if search != curr_search:
                boxes_clicked_this_search = set()
                curr_search = search
                
            # Compute BSE and WSE
            if box in boxes_with_tokens:
                gt_stats[pid]['total_bse'] += 1
            elif box in boxes_clicked_this_search:
                gt_stats[pid]['total_wse'] += 1
            else:
                boxes_clicked_this_search.add(box)
                
            # Record tokens found
            if found == 1:
                boxes_with_tokens.add(box)
                
            # Track first clicks for strategy score
            if bcount in (6, 8) and click_seq == 1:
                if trial not in gt_stats[pid]['trials_strat']:
                    gt_stats[pid]['trials_strat'][trial] = set()
                gt_stats[pid]['trials_strat'][trial].add(box)

    # Resolve strategy scores
    for pid, stats in gt_stats.items():
        strat_score = 0
        for trial_num, first_clicks in stats['trials_strat'].items():
            strat_score += len(first_clicks)
        stats['strategy_score'] = strat_score
        del stats['trials_strat']
        
    return gt_stats

def verify_swm_heuristic_strategy_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 0. Retrieve ground truth data file to compute true values
    gt_data_path = None
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        gt_data_path = tmp_csv.name
        
    try:
        copy_from_env('/tmp/swm_click_logs_gt.csv', gt_data_path)
        GROUND_TRUTH = compute_ground_truth(gt_data_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not compute ground truth: {e}"}
    finally:
        if os.path.exists(gt_data_path):
            os.unlink(gt_data_path)

    # 1. Retrieve agent's report
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json:
        tmp_report_path = tmp_json.name

    try:
        copy_from_env('/home/ga/pebl/analysis/swm_report.json', tmp_report_path)
        with open(tmp_report_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/swm_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(tmp_report_path):
            os.unlink(tmp_report_path)

    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and pid in excluded_list:
            return True
        return False

    # Identify true contaminated (WSE > 50)
    contaminated_pids = [pid for pid, stats in GROUND_TRUTH.items() if stats['total_wse'] > 50]
    expected_contam = contaminated_pids[0] if contaminated_pids else "sub-99"

    # 2. Check exclusion logic
    if is_excluded(expected_contam):
        score += 20
        feedback_parts.append(f'[+20] {expected_contam} correctly excluded (WSE > 50).')
    else:
        feedback_parts.append(f'[0] {expected_contam} not excluded despite having WSE > 50.')

    # Evaluate metrics for valid participants
    valid_pids = [pid for pid in GROUND_TRUTH.keys() if pid not in contaminated_pids]
    
    correct_wse = 0
    correct_bse = 0
    correct_strat = 0
    
    for pid in valid_pids:
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
            
        gt = GROUND_TRUTH[pid]
        
        # WSE Check
        wse = entry.get('total_wse')
        if wse is not None:
            try:
                if int(float(wse)) == gt['total_wse']:
                    correct_wse += 1
            except ValueError:
                pass
                
        # BSE Check
        bse = entry.get('total_bse')
        if bse is not None:
            try:
                if int(float(bse)) == gt['total_bse']:
                    correct_bse += 1
            except ValueError:
                pass
                
        # Strategy Check
        strat = entry.get('strategy_score')
        if strat is not None:
            try:
                if int(float(strat)) == gt['strategy_score']:
                    correct_strat += 1
            except ValueError:
                pass

    # 3. Score WSE
    if correct_wse >= 12:
        score += 20
        feedback_parts.append(f'[+20] total_wse correct for {correct_wse}/{len(valid_pids)} valid participants.')
    elif correct_wse >= 6:
        score += 10
        feedback_parts.append(f'[+10] total_wse correct for {correct_wse}/{len(valid_pids)} valid participants (partial).')
    else:
        feedback_parts.append(f'[0] total_wse correct for only {correct_wse}/{len(valid_pids)} valid participants.')

    # 4. Score BSE
    if correct_bse >= 12:
        score += 20
        feedback_parts.append(f'[+20] total_bse correct for {correct_bse}/{len(valid_pids)} valid participants.')
    elif correct_bse >= 6:
        score += 10
        feedback_parts.append(f'[+10] total_bse correct for {correct_bse}/{len(valid_pids)} valid participants (partial).')
    else:
        feedback_parts.append(f'[0] total_bse correct for only {correct_bse}/{len(valid_pids)} valid participants.')

    # 5. Score Strategy
    if correct_strat >= 12:
        score += 15
        feedback_parts.append(f'[+15] strategy_score correct for {correct_strat}/{len(valid_pids)} valid participants.')
    elif correct_strat >= 6:
        score += 7
        feedback_parts.append(f'[+7] strategy_score correct for {correct_strat}/{len(valid_pids)} valid participants (partial).')
    else:
        feedback_parts.append(f'[0] strategy_score correct for only {correct_strat}/{len(valid_pids)} valid participants.')

    # 6. Score Group Means
    group_means = report.get('group_means', {})
    rep_mean_bse = group_means.get('mean_bse')
    rep_mean_wse = group_means.get('mean_wse')
    rep_mean_strat = group_means.get('mean_strategy')
    
    true_mean_bse = statistics.mean([GROUND_TRUTH[p]['total_bse'] for p in valid_pids])
    true_mean_wse = statistics.mean([GROUND_TRUTH[p]['total_wse'] for p in valid_pids])
    true_mean_strat = statistics.mean([GROUND_TRUTH[p]['strategy_score'] for p in valid_pids])
    
    means_correct = 0
    try:
        if rep_mean_bse is not None and abs(float(rep_mean_bse) - true_mean_bse) <= 0.5: means_correct += 1
        if rep_mean_wse is not None and abs(float(rep_mean_wse) - true_mean_wse) <= 0.5: means_correct += 1
        if rep_mean_strat is not None and abs(float(rep_mean_strat) - true_mean_strat) <= 0.5: means_correct += 1
    except (TypeError, ValueError):
        pass

    if means_correct == 3:
        score += 15
        feedback_parts.append('[+15] All 3 group means are correct within ±0.5.')
    elif means_correct > 0:
        score += 5
        feedback_parts.append(f'[+5] {means_correct}/3 group means are correct (partial).')
    else:
        feedback_parts.append('[0] Group means are incorrect or missing.')

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }