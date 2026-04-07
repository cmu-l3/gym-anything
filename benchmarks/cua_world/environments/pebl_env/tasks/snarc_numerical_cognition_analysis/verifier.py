#!/usr/bin/env python3
"""
Verifier for snarc_numerical_cognition_analysis task.

Since the CSV data is stochastically generated on every run, the verifier dynamically parses
the actual CSV file the agent operated on to compute the exact ground truth.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant sub-99 is excluded                      (20 pts)
  3. SNARC slopes correct for >= 18 valid ppts                     (40 pts)
  4. Accuracy & Mean RT correct for >= 18 valid ppts               (15 pts)
  5. Group mean slope correct (within tolerance)                   (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import csv
from collections import defaultdict


def compute_ground_truth(csv_path):
    """
    Computes exact ground truth matching the task instructions.
    """
    data = defaultdict(list)
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data[row['participant_id']].append(row)
            
    results = {}
    for pid, rows in data.items():
        if pid == 'sub-99': 
            continue
            
        # Accuracy: Blocks 2 & 3, prior to RT filtering
        b23_rows = [r for r in rows if int(r['block']) in [2, 3]]
        acc = sum(1 for r in b23_rows if int(r['correct']) == 1) / len(b23_rows) if b23_rows else 0.0
        
        # RT filtering: correct==1, 200 <= rt_ms <= 1500
        valid_rows = [r for r in b23_rows if int(r['correct']) == 1 and 200 <= float(r['rt_ms']) <= 1500]
        mean_rt = sum(float(r['rt_ms']) for r in valid_rows) / len(valid_rows) if valid_rows else 0.0
        
        # SNARC slope: Predict dRT (mean_RT_Right - mean_RT_Left) from number
        num_rt = defaultdict(lambda: {'left': [], 'right': []})
        for r in valid_rows:
            num = int(r['number'])
            hand = r['response_hand'].lower().strip()
            num_rt[num][hand].append(float(r['rt_ms']))
            
        numbers = []
        drts = []
        for num in sorted(num_rt.keys()):
            lefts = num_rt[num]['left']
            rights = num_rt[num]['right']
            if lefts and rights:
                mean_l = sum(lefts)/len(lefts)
                mean_r = sum(rights)/len(rights)
                numbers.append(num)
                drts.append(mean_r - mean_l)
                
        if len(numbers) > 1:
            n = len(numbers)
            mean_x = sum(numbers) / n
            mean_y = sum(drts) / n
            cov = sum((x - mean_x)*(y - mean_y) for x, y in zip(numbers, drts))
            var = sum((x - mean_x)**2 for x in numbers)
            slope = cov / var if var != 0 else 0.0
        else:
            slope = 0.0
            
        results[pid] = {
            'overall_accuracy': acc,
            'mean_rt_ms': mean_rt,
            'snarc_slope': slope
        }
        
    return results


def verify_snarc_numerical_cognition_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy mechanism missing."}
        
    report_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    report_path = report_tmp.name
    csv_path = csv_tmp.name
    report_tmp.close()
    csv_tmp.close()
    
    score = 0
    feedback = []
    
    try:
        # Load the agent's report
        try:
            copy_from_env('/home/ga/pebl/analysis/snarc_report.json', report_path)
            with open(report_path, 'r', encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback.append("[+10] Output file found and is valid JSON.")
        except FileNotFoundError:
            feedback.append("[0] Output file /home/ga/pebl/analysis/snarc_report.json not found.")
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
        except (json.JSONDecodeError, ValueError) as e:
            feedback.append(f"[0] Output file exists but is not valid JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

        # Load the data and dynamically calculate exact ground truth
        try:
            copy_from_env('/home/ga/pebl/data/snarc_data.csv', csv_path)
            ground_truth = compute_ground_truth(csv_path)
        except Exception as e:
            feedback.append(f"Failed to calculate verification ground truth: {e}")
            return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}
            
        agent_participants = report.get('participants', [])
        part_map = {}
        for p in agent_participants:
            pid = p.get('id') or p.get('participant_id') or p.get('participant')
            if pid:
                part_map[str(pid)] = p
                
        def is_excluded(entry, pid):
            if not entry:
                excluded_list = report.get('excluded', [])
                if isinstance(excluded_list, list) and pid in excluded_list:
                    return True
                return False
            return entry.get('excluded') in (True, 'true', 1, 'yes')
            
        # Check sub-99 exclusion
        if is_excluded(part_map.get('sub-99'), 'sub-99'):
            score += 20
            feedback.append("[+20] Anomalous participant sub-99 correctly excluded.")
        else:
            feedback.append("[0] sub-99 not excluded despite impossible (zero) RT variance.")
            
        # Verify SNARC Slopes and Accuracy/RT
        correct_slopes = 0
        correct_acc_rt = 0
        
        for pid, gt_vals in ground_truth.items():
            agent_p = part_map.get(pid)
            if agent_p and not is_excluded(agent_p, pid):
                
                # Verify slope (generous ±0.5 ms/digit tolerance)
                slope = agent_p.get("snarc_slope")
                if slope is not None and abs(float(slope) - gt_vals["snarc_slope"]) <= 0.5:
                    correct_slopes += 1
                elif slope is not None:
                    feedback.append(f"  -> PID {pid} slope mismatch (Agent: {slope}, GT: {gt_vals['snarc_slope']:.2f})")
                    
                # Verify accuracy (±0.02) & RT (±5ms)
                acc = agent_p.get("overall_accuracy")
                rt = agent_p.get("mean_rt_ms")
                if acc is not None and rt is not None:
                    if abs(float(acc) - gt_vals["overall_accuracy"]) <= 0.02 and abs(float(rt) - gt_vals["mean_rt_ms"]) <= 5.0:
                        correct_acc_rt += 1
                        
        if correct_slopes >= 18:
            score += 40
            feedback.append(f"[+40] SNARC slopes correct for {correct_slopes}/20 valid participants.")
        elif correct_slopes >= 10:
            score += 20
            feedback.append(f"[+20] SNARC slopes correct for {correct_slopes}/20 valid participants (partial).")
        else:
            feedback.append(f"[0] SNARC slopes correct for only {correct_slopes}/20 valid participants.")
            
        if correct_acc_rt >= 18:
            score += 15
            feedback.append(f"[+15] Accuracy and Mean RT correct for {correct_acc_rt}/20 valid participants.")
        elif correct_acc_rt >= 10:
            score += 7
            feedback.append(f"[+7] Accuracy and Mean RT correct for {correct_acc_rt}/20 valid participants (partial).")
        else:
            feedback.append(f"[0] Accuracy and Mean RT correct for only {correct_acc_rt}/20 valid participants.")
            
        # Check Group Mean Slope
        gt_group_mean_slope = sum(v['snarc_slope'] for v in ground_truth.values()) / len(ground_truth)
        agent_group_slope = report.get('group_mean_snarc_slope')
        
        if agent_group_slope is not None and abs(float(agent_group_slope) - gt_group_mean_slope) <= 1.0:
            score += 15
            feedback.append(f"[+15] Group mean slope correct (Expected: {gt_group_mean_slope:.2f}, Got: {agent_group_slope}).")
        else:
            feedback.append(f"[0] Group mean slope incorrect or missing (Expected: {gt_group_mean_slope:.2f}, Got: {agent_group_slope}).")
            
    finally:
        os.unlink(report_path)
        os.unlink(csv_path)
        
    passed = score >= 60
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback)}