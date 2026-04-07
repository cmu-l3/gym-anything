#!/usr/bin/env python3
"""
Verifier for tmt_executive_cost_analysis task.

This verifier pulls BOTH the agent's generated report and the source CSV 
from the container. It dynamically computes the ground truth from the CSV 
to ensure absolute accuracy, then evaluates the agent's JSON output.

Scoring (100 pts total):
  1. File Output (10 pts)
  2. Anomaly Detection: P99 excluded (20 pts)
  3. Aggregated Times: A/B times correct for valid ppts (20 pts)
  4. Error Counts: A/B errors correct for valid ppts (15 pts)
  5. Derived Metrics: Cost and Ratio correct (20 pts)
  6. Group Statistics: Group means correct without P99 (15 pts)
"""

import json
import os
import csv
import tempfile

def compute_ground_truth(csv_path):
    """Computes exact ground truth directly from the agent's dataset."""
    data = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            part = row['test_part']
            err = int(row['error_flag'])
            rt = int(row['rt_ms'])
            
            if pid not in data:
                data[pid] = {'A_time': 0, 'B_time': 0, 'A_err': 0, 'B_err': 0}
            
            if part == 'A':
                data[pid]['A_time'] += rt
                data[pid]['A_err'] += err
            elif part == 'B':
                data[pid]['B_time'] += rt
                data[pid]['B_err'] += err

    results = {}
    valid_costs = []
    valid_ratios = []
    
    for pid, metrics in data.items():
        time_a_s = metrics['A_time'] / 1000.0
        time_b_s = metrics['B_time'] / 1000.0
        cost = time_b_s - time_a_s
        ratio = time_b_s / time_a_s if time_a_s > 0 else 0
        
        results[pid] = {
            'tmt_a_time_s': time_a_s,
            'tmt_b_time_s': time_b_s,
            'tmt_a_errors': metrics['A_err'],
            'tmt_b_errors': metrics['B_err'],
            'b_minus_a_cost_s': cost,
            'b_over_a_ratio': ratio
        }
        
        if pid != "P99":
            valid_costs.append(cost)
            valid_ratios.append(ratio)
            
    group_cost = sum(valid_costs) / len(valid_costs) if valid_costs else 0
    group_ratio = sum(valid_ratios) / len(valid_ratios) if valid_ratios else 0
    
    return results, group_cost, group_ratio

def verify_tmt_executive_cost_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    report_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False).name

    try:
        # Pull CSV to compute Ground Truth
        try:
            copy_from_env('/home/ga/pebl/data/tmt_click_log.csv', csv_tmp)
            gt_data, gt_group_cost, gt_group_ratio = compute_ground_truth(csv_tmp)
        except Exception as e:
            return {'passed': False, 'score': 0, 'feedback': f'Failed to parse GT CSV: {e}'}

        # Pull Agent's Report
        try:
            copy_from_env('/home/ga/pebl/analysis/tmt_report.json', report_tmp)
            with open(report_tmp, 'r', encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append('[+10] Report valid JSON.')
        except FileNotFoundError:
            feedback_parts.append('[0] Report not found.')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
        except json.JSONDecodeError:
            feedback_parts.append('[0] Report invalid JSON.')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

        # Build participant map
        participants = report.get('participants', [])
        part_map = {}
        for p in participants:
            pid = p.get('id') or p.get('participant_id')
            if pid:
                part_map[str(pid)] = p

        # 2. Anomaly Detection
        p99 = part_map.get("P99", {})
        if p99.get('excluded') in (True, 'true', 1, 'yes'):
            score += 20
            feedback_parts.append('[+20] P99 correctly excluded.')
        else:
            feedback_parts.append('[0] P99 NOT excluded.')

        # Verification counters
        correct_times = 0
        correct_errors = 0
        correct_derived = 0
        valid_pids = [p for p in gt_data.keys() if p != "P99"]

        # 3, 4, 5. Per-participant metric checks
        for pid in valid_pids:
            agt = part_map.get(pid, {})
            gt = gt_data[pid]
            
            if agt.get('excluded'):
                continue
                
            try:
                # Times
                ta = float(agt.get('tmt_a_time_s', -1))
                tb = float(agt.get('tmt_b_time_s', -1))
                if abs(ta - gt['tmt_a_time_s']) < 0.05 and abs(tb - gt['tmt_b_time_s']) < 0.05:
                    correct_times += 1
                
                # Errors
                ea = int(agt.get('tmt_a_errors', -1))
                eb = int(agt.get('tmt_b_errors', -1))
                if ea == gt['tmt_a_errors'] and eb == gt['tmt_b_errors']:
                    correct_errors += 1
                    
                # Derived
                cost = float(agt.get('b_minus_a_cost_s', -1))
                ratio = float(agt.get('b_over_a_ratio', -1))
                if abs(cost - gt['b_minus_a_cost_s']) < 0.05 and abs(ratio - gt['b_over_a_ratio']) < 0.05:
                    correct_derived += 1
            except (TypeError, ValueError):
                pass

        total_valid = len(valid_pids) # Should be 31
        
        if correct_times >= 28:
            score += 20
            feedback_parts.append(f'[+20] Base times correct ({correct_times}/{total_valid}).')
        else:
            feedback_parts.append(f'[0] Base times correct for only {correct_times}/{total_valid}.')

        if correct_errors >= 28:
            score += 15
            feedback_parts.append(f'[+15] Errors correct ({correct_errors}/{total_valid}).')
        else:
            feedback_parts.append(f'[0] Errors correct for only {correct_errors}/{total_valid}.')

        if correct_derived >= 28:
            score += 20
            feedback_parts.append(f'[+20] Derived metrics correct ({correct_derived}/{total_valid}).')
        else:
            feedback_parts.append(f'[0] Derived metrics correct for only {correct_derived}/{total_valid}.')

        # 6. Group Statistics
        try:
            grp_cost = float(report.get('group_mean_b_minus_a_cost_s', -1))
            grp_ratio = float(report.get('group_mean_b_over_a_ratio', -1))
            
            if abs(grp_cost - gt_group_cost) < 0.05 and abs(grp_ratio - gt_group_ratio) < 0.05:
                score += 15
                feedback_parts.append('[+15] Group statistics correct.')
            else:
                feedback_parts.append(f'[0] Group stats incorrect. Expected cost:{gt_group_cost:.2f}, ratio:{gt_group_ratio:.2f}.')
        except (TypeError, ValueError):
            feedback_parts.append('[0] Group statistics missing or invalid format.')

    finally:
        if os.path.exists(report_tmp): os.unlink(report_tmp)
        if os.path.exists(csv_tmp): os.unlink(csv_tmp)

    passed = score >= 60 and part_map.get("P99", {}).get('excluded') in (True, 'true', 1, 'yes')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }