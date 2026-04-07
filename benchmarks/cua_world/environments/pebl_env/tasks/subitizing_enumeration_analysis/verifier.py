#!/usr/bin/env python3
"""
Verifier for subitizing_enumeration_analysis task.

Dynamically computes exact ground truth from the CSV file present in the container
to ensure completely robust verification unaffected by floating-point edge cases.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                       (10 pts)
  2. Contamination (sub-99) excluded                            (20 pts)
  3. Accuracy correctly calculated (±0.02) for ≥15 participants (20 pts)
  4. Subitizing slopes calculated (±2.0ms) for ≥15 participants (20 pts)
  5. Counting slopes calculated (±2.0ms) for ≥15 participants   (20 pts)
  6. Group means calculated correctly (±1.0ms)                  (10 pts)
"""

import json
import os
import tempfile
import csv

def linregress(x, y):
    """Simple linear regression slope calculation"""
    n = len(x)
    if n == 0: return 0.0
    sum_x = sum(x)
    sum_y = sum(y)
    sum_x2 = sum(xi*xi for xi in x)
    sum_xy = sum(xi*yi for xi, yi in zip(x, y))
    denominator = (n * sum_x2 - sum_x**2)
    if denominator == 0: return 0.0
    return (n * sum_xy - sum_x * sum_y) / denominator


def verify_subitizing_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # ==========================================
    # 1. Fetch JSON and CSV files
    # ==========================================
    report_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json, \
         tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        json_path = tmp_json.name
        csv_path = tmp_csv.name

    try:
        copy_from_env('/home/ga/pebl/analysis/subitizing_report.json', json_path)
        with open(json_path, encoding='utf-8') as f:
            report_data = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/subitizing_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file invalid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
        
    try:
        copy_from_env('/home/ga/pebl/data/enumeration_data.csv', csv_path)
    except Exception as e:
        feedback_parts.append(f"Failed to copy CSV dataset for ground truth comparison: {e}")
        return {'passed': False, 'score': score, 'feedback': ' '.join(feedback_parts)}

    # ==========================================
    # 2. Compute Exact Ground Truth from CSV
    # ==========================================
    gt_stats = {}
    valid_participants = set()
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        data = list(reader)
    
    # Identify unique participants
    pids = sorted(list(set(r['participant_id'] for r in data)))
    
    for pid in pids:
        if pid == 'sub-99': continue
        valid_participants.add(pid)
        p_data = [r for r in data if r['participant_id'] == pid]
        
        # Accuracies
        small_range = [int(r['correct']) for r in p_data if 1 <= int(r['dot_count']) <= 4]
        large_range = [int(r['correct']) for r in p_data if 5 <= int(r['dot_count']) <= 9]
        acc_1_4 = sum(small_range) / len(small_range) if small_range else 0.0
        acc_5_9 = sum(large_range) / len(large_range) if large_range else 0.0
        
        # Slopes (Correct trials only)
        sub_x = [int(r['dot_count']) for r in p_data if int(r['correct']) == 1 and int(r['dot_count']) in [1,2,3]]
        sub_y = [float(r['rt_ms']) for r in p_data if int(r['correct']) == 1 and int(r['dot_count']) in [1,2,3]]
        sub_slope = linregress(sub_x, sub_y)
        
        count_x = [int(r['dot_count']) for r in p_data if int(r['correct']) == 1 and int(r['dot_count']) in [5,6,7,8]]
        count_y = [float(r['rt_ms']) for r in p_data if int(r['correct']) == 1 and int(r['dot_count']) in [5,6,7,8]]
        count_slope = linregress(count_x, count_y)
        
        gt_stats[pid] = {
            'acc_1_4': acc_1_4,
            'acc_5_9': acc_5_9,
            'sub_slope': sub_slope,
            'count_slope': count_slope
        }
    
    gt_group_sub = sum(v['sub_slope'] for v in gt_stats.values()) / len(gt_stats)
    gt_group_count = sum(v['count_slope'] for v in gt_stats.values()) / len(gt_stats)

    # Clean up temp files
    try:
        os.unlink(json_path)
        os.unlink(csv_path)
    except Exception:
        pass

    # ==========================================
    # 3. Evaluate Agent's JSON Output
    # ==========================================
    participants_list = report_data.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'): return True
        return False

    # Check contamination
    if is_excluded('sub-99'):
        score += 20
        feedback_parts.append('[+20] Participant sub-99 correctly excluded.')
    elif 'sub-99' not in part_map:
        # Check if there's a top-level excluded list
        excluded_list = report_data.get('excluded', [])
        if 'sub-99' in excluded_list:
            score += 20
            feedback_parts.append('[+20] Participant sub-99 correctly excluded.')
        else:
            feedback_parts.append('[0] sub-99 not excluded despite obvious response-mashing artifact.')
    else:
        feedback_parts.append('[0] sub-99 not excluded despite obvious response-mashing artifact.')

    correct_acc = 0
    correct_sub = 0
    correct_count = 0

    for pid in valid_participants:
        entry = part_map.get(pid, {})
        if not entry or is_excluded(pid):
            continue
            
        try:
            acc1 = float(entry.get('accuracy_1_to_4', -1))
            acc5 = float(entry.get('accuracy_5_to_9', -1))
            ss = float(entry.get('subitizing_slope_ms', -1))
            cs = float(entry.get('counting_slope_ms', -1))
            
            if abs(acc1 - gt_stats[pid]['acc_1_4']) <= 0.02 and abs(acc5 - gt_stats[pid]['acc_5_9']) <= 0.02:
                correct_acc += 1
                
            if abs(ss - gt_stats[pid]['sub_slope']) <= 2.0:
                correct_sub += 1
                
            if abs(cs - gt_stats[pid]['count_slope']) <= 2.0:
                correct_count += 1
                
        except (ValueError, TypeError):
            continue

    if correct_acc >= 15:
        score += 20
        feedback_parts.append(f'[+20] Accuracies correct for {correct_acc}/18 participants.')
    elif correct_acc >= 8:
        score += 10
        feedback_parts.append(f'[+10] Accuracies correct for {correct_acc}/18 participants (partial).')
    else:
        feedback_parts.append(f'[0] Accuracies correct for only {correct_acc}/18 participants.')

    if correct_sub >= 15:
        score += 20
        feedback_parts.append(f'[+20] Subitizing slopes correct for {correct_sub}/18 participants.')
    elif correct_sub >= 8:
        score += 10
        feedback_parts.append(f'[+10] Subitizing slopes correct for {correct_sub}/18 participants (partial).')
    else:
        feedback_parts.append(f'[0] Subitizing slopes correct for only {correct_sub}/18 participants.')

    if correct_count >= 15:
        score += 20
        feedback_parts.append(f'[+20] Counting slopes correct for {correct_count}/18 participants.')
    elif correct_count >= 8:
        score += 10
        feedback_parts.append(f'[+10] Counting slopes correct for {correct_count}/18 participants (partial).')
    else:
        feedback_parts.append(f'[0] Counting slopes correct for only {correct_count}/18 participants.')

    # Group Means
    agent_sub_mean = report_data.get('group_mean_subitizing_slope_ms', -999)
    agent_count_mean = report_data.get('group_mean_counting_slope_ms', -999)
    
    means_correct = 0
    try:
        if abs(float(agent_sub_mean) - gt_group_sub) <= 1.0: means_correct += 1
        if abs(float(agent_count_mean) - gt_group_count) <= 1.0: means_correct += 1
    except (ValueError, TypeError):
        pass

    if means_correct == 2:
        score += 10
        feedback_parts.append('[+10] Both group means calculated accurately.')
    elif means_correct == 1:
        score += 5
        feedback_parts.append('[+5] One group mean calculated accurately.')
    else:
        feedback_parts.append('[0] Group means missing or inaccurate.')

    key_criteria_met = (correct_sub >= 8 and correct_count >= 8 and is_excluded('sub-99'))
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }