#!/usr/bin/env python3
"""
Verifier for drm_false_memory_analysis task.

Computes the ground truth dynamically from the hidden CSV dataset.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant sub-99 is correctly excluded            (25 pts)
  3. All 25 valid participants are present                         (15 pts)
  4. Individual recognition/FA rates are accurate within ±0.02     (30 pts)
  5. Group means are accurate within ±0.02                         (20 pts)

Pass threshold: 70 pts AND the contaminated participant must be excluded.
"""

import json
import os
import tempfile
import csv


def verify_drm_false_memory_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # --- Criterion 1: Output file exists and is valid JSON ---
    report_file = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    report = None
    try:
        copy_from_env('/home/ga/pebl/analysis/drm_report.json', report_file.name)
        with open(report_file.name, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Report found and is valid JSON.')
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "[0] Output file /home/ga/pebl/analysis/drm_report.json not found."}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"[0] Output file is not valid JSON: {e}"}
    finally:
        if os.path.exists(report_file.name):
            os.unlink(report_file.name)
            
    # --- Compute Ground Truth from hidden original CSV ---
    gt_file = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    gt_stats = {}
    try:
        copy_from_env('/tmp/.drm_ground_truth.csv', gt_file.name)
        with open(gt_file.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                pid = row['participant_id']
                cond = row['condition']
                resp = int(row['response'])
                if pid not in gt_stats:
                    gt_stats[pid] = {'studied': [], 'critical_lure': [], 'unrelated': []}
                if cond in gt_stats[pid]:
                    gt_stats[pid][cond].append(resp)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(gt_file.name):
            os.unlink(gt_file.name)
            
    gt_means = {}
    for pid, conds in gt_stats.items():
        if pid == 'sub-99': continue
        gt_means[pid] = {
            'true_recognition_rate': sum(conds['studied'])/len(conds['studied']) if conds['studied'] else 0,
            'critical_false_memory_rate': sum(conds['critical_lure'])/len(conds['critical_lure']) if conds['critical_lure'] else 0,
            'baseline_false_alarm_rate': sum(conds['unrelated'])/len(conds['unrelated']) if conds['unrelated'] else 0,
        }

    group_means_gt = {
        'true_recognition_rate': sum(m['true_recognition_rate'] for m in gt_means.values()) / len(gt_means),
        'critical_false_memory_rate': sum(m['critical_false_memory_rate'] for m in gt_means.values()) / len(gt_means),
        'baseline_false_alarm_rate': sum(m['baseline_false_alarm_rate'] for m in gt_means.values()) / len(gt_means)
    }

    participants = report.get('participants', [])
    if not isinstance(participants, list):
        return {"passed": False, "score": score, "feedback": "JSON missing 'participants' list."}

    part_map = {}
    for p in participants:
        pid = p.get('id') or p.get('participant_id')
        if pid:
            part_map[pid] = p

    # --- Criterion 2: Corrupted participant sub-99 excluded ---
    excluded = False
    s99 = part_map.get('sub-99')
    if s99 and s99.get('excluded') in [True, 'true', 'Yes', 1]:
        excluded = True
    elif 'sub-99' not in part_map:
        if 'sub-99' in report.get('excluded', []):
            excluded = True

    if excluded:
        score += 25
        feedback_parts.append('[+25] Contaminated participant sub-99 correctly excluded.')
    else:
        feedback_parts.append('[0] sub-99 not excluded despite impossible RT profile.')

    # --- Criterion 3: All valid participants present ---
    valid_present = 0
    for pid in gt_means.keys():
        if pid in part_map and part_map[pid].get('excluded') not in [True, 'true', 'Yes', 1]:
            valid_present += 1
            
    if valid_present == len(gt_means):
        score += 15
        feedback_parts.append(f'[+15] All {len(gt_means)} valid participants present.')
    else:
        pts = int((valid_present / len(gt_means)) * 15)
        score += pts
        feedback_parts.append(f'[+{pts}] {valid_present}/{len(gt_means)} valid participants present.')

    # --- Criterion 4: Individual Rates Accurate ---
    correct_rates = 0
    total_rates = len(gt_means) * 3
    for pid, gt_vals in gt_means.items():
        p_data = part_map.get(pid, {})
        for metric in ['true_recognition_rate', 'critical_false_memory_rate', 'baseline_false_alarm_rate']:
            val = p_data.get(metric)
            if val is not None:
                try:
                    if abs(float(val) - gt_vals[metric]) <= 0.02:
                        correct_rates += 1
                except (ValueError, TypeError):
                    pass

    rate_pts = int((correct_rates / total_rates) * 30)
    score += rate_pts
    feedback_parts.append(f'[+{rate_pts}] {correct_rates}/{total_rates} individual metrics accurate within ±0.02.')

    # --- Criterion 5: Group Means Accurate ---
    correct_group = 0
    rep_group = report.get('group_means', {})
    for metric, gt_val in group_means_gt.items():
        val = rep_group.get(metric)
        if val is not None:
            try:
                if abs(float(val) - gt_val) <= 0.02:
                    correct_group += 1
            except (ValueError, TypeError):
                pass
                
    group_pts = int((correct_group / 3) * 20)
    score += group_pts
    feedback_parts.append(f'[+{group_pts}] {correct_group}/3 group mean metrics accurate within ±0.02.')

    passed = score >= 70 and excluded
    return {"passed": passed, "score": score, "feedback": " ".join(feedback_parts)}