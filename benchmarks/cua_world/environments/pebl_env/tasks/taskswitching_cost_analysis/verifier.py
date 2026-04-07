#!/usr/bin/env python3
"""
Verifier for taskswitching_cost_analysis task.

Calculates the ground truth dynamically from the provided data set,
ensuring perfect scoring matches even if data changes or is synthesized.
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_ground_truth(csv_path):
    participants = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in participants:
                participants[pid] = {'trials': []}
            participants[pid]['trials'].append({
                'trial_type': row['trial_type'],
                'correct': int(row['correct']),
                'rt_ms': int(row['rt_ms'])
            })
            
    results = {}
    for pid, data in participants.items():
        if pid == 'sub-99999':
            continue
            
        trials = data['trials']
        # 1 & 2. Exclude FIRST trials and rt == 0
        valid_trials = [t for t in trials if t['trial_type'] in ('SWITCH', 'REPEAT') and t['rt_ms'] > 0]
        
        sw_trials = [t for t in valid_trials if t['trial_type'] == 'SWITCH']
        rep_trials = [t for t in valid_trials if t['trial_type'] == 'REPEAT']
        
        if not sw_trials or not rep_trials:
            continue
            
        sw_acc = sum(t['correct'] for t in sw_trials) / len(sw_trials)
        rep_acc = sum(t['correct'] for t in rep_trials) / len(rep_trials)
        
        # RT is computed on CORRECT trials only
        sw_correct = [t for t in sw_trials if t['correct'] == 1]
        rep_correct = [t for t in rep_trials if t['correct'] == 1]
        
        sw_rt = sum(t['rt_ms'] for t in sw_correct) / len(sw_correct) if sw_correct else 0
        rep_rt = sum(t['rt_ms'] for t in rep_correct) / len(rep_correct) if rep_correct else 0
        
        rt_cost = sw_rt - rep_rt
        acc_cost = rep_acc - sw_acc
        
        results[pid] = {
            'mean_rt_switch_ms': sw_rt,
            'mean_rt_repeat_ms': rep_rt,
            'accuracy_switch': sw_acc,
            'accuracy_repeat': rep_acc,
            'rt_switch_cost_ms': rt_cost,
            'accuracy_switch_cost': acc_cost
        }
        
    group_rt_cost = sum(r['rt_switch_cost_ms'] for r in results.values()) / len(results)
    group_acc_cost = sum(r['accuracy_switch_cost'] for r in results.values()) / len(results)
    
    return results, group_rt_cost, group_acc_cost

def verify_taskswitching_cost_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Compute ground truth dynamically
    gt_csv_path = tempfile.NamedTemporaryFile(suffix='.csv', delete=False).name
    try:
        copy_from_env('/tmp/ground_truth_data.csv', gt_csv_path)
        gt_results, gt_group_rt, gt_group_acc = compute_ground_truth(gt_csv_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to compute ground truth from CSV: {e}"}
    finally:
        if os.path.exists(gt_csv_path):
            os.unlink(gt_csv_path)
            
    # 2. Extract agent's reported JSON
    report_path = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name
    try:
        copy_from_env('/home/ga/pebl/analysis/taskswitching_report.json', report_path)
        with open(report_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/taskswitching_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(report_path):
            os.unlink(report_path)
            
    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = (entry.get('id') or entry.get('participant_id') or entry.get('participant'))
        if pid:
            part_map[str(pid)] = entry
            
    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        if pid not in part_map:
            excluded_list = report.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
        return False
        
    # Criterion 2: Contaminated sub-99999 excluded (20 points)
    if is_excluded('sub-99999'):
        score += 20
        feedback_parts.append('[+20] sub-99999 correctly excluded.')
    else:
        feedback_parts.append('[0] sub-99999 not excluded.')
        
    # Check that all 11 real participants are present (15 points)
    present_count = 0
    for pid in gt_results:
        if pid in part_map and not is_excluded(pid):
            entry = part_map[pid]
            # Verify they reported the necessary stats
            fields = ['mean_rt_switch_ms', 'mean_rt_repeat_ms', 'accuracy_switch', 'accuracy_repeat', 'rt_switch_cost_ms', 'accuracy_switch_cost']
            if all(f in entry for f in fields):
                present_count += 1
                
    if present_count == 11:
        score += 15
        feedback_parts.append('[+15] All 11 valid participants present with required fields.')
    elif present_count > 0:
        partial = int((present_count / 11.0) * 15)
        score += partial
        feedback_parts.append(f'[+{partial}] {present_count}/11 participants present with required fields.')
    else:
        feedback_parts.append('[0] Missing valid participants or required fields.')
        
    # Accuracy checks (RT and Accuracy Costs)
    rt_correct = 0
    acc_correct = 0
    
    for pid, gt in gt_results.items():
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
            
        rt_cost = entry.get('rt_switch_cost_ms')
        if rt_cost is not None:
            try:
                # Accept both standard formulation and inverse sign just in case
                val = float(rt_cost)
                if abs(val - gt['rt_switch_cost_ms']) <= 30.0 or abs(val - (-gt['rt_switch_cost_ms'])) <= 30.0:
                    rt_correct += 1
            except (ValueError, TypeError):
                pass
                
        acc_cost = entry.get('accuracy_switch_cost')
        if acc_cost is not None:
            try:
                val = float(acc_cost)
                if abs(val - gt['accuracy_switch_cost']) <= 0.05 or abs(val - (-gt['accuracy_switch_cost'])) <= 0.05:
                    acc_correct += 1
            except (ValueError, TypeError):
                pass
                
    if rt_correct >= 8:
        score += 25
        feedback_parts.append(f'[+25] RT switch costs accurate for {rt_correct}/11 participants.')
    elif rt_correct > 0:
        partial = int((rt_correct / 11.0) * 25)
        score += partial
        feedback_parts.append(f'[+{partial}] RT switch costs accurate for {rt_correct}/11 participants.')
    else:
        feedback_parts.append('[0] RT switch costs inaccurate.')
        
    if acc_correct >= 8:
        score += 15
        feedback_parts.append(f'[+15] Accuracy switch costs accurate for {acc_correct}/11 participants.')
    elif acc_correct > 0:
        partial = int((acc_correct / 11.0) * 15)
        score += partial
        feedback_parts.append(f'[+{partial}] Accuracy switch costs accurate for {acc_correct}/11 participants.')
    else:
        feedback_parts.append('[0] Accuracy switch costs inaccurate.')
        
    # Group Mean RT Switch Cost (15 points)
    grp_rt_cost = report.get('group_mean_rt_switch_cost_ms')
    if grp_rt_cost is not None:
        try:
            val = float(grp_rt_cost)
            if abs(val - gt_group_rt) <= 20.0 or abs(val - (-gt_group_rt)) <= 20.0:
                score += 15
                feedback_parts.append('[+15] Group mean RT switch cost is accurate.')
            else:
                feedback_parts.append(f'[0] Group mean RT switch cost {grp_rt_cost} is outside tolerance (expected ~{gt_group_rt:.1f}).')
        except (ValueError, TypeError):
            feedback_parts.append('[0] Invalid group mean format.')
    else:
        feedback_parts.append('[0] Group mean RT switch cost missing.')
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }