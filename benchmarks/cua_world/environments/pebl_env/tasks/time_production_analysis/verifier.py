#!/usr/bin/env python3
"""
Verifier for time_production_analysis task.

Since the CSV is generated dynamically at runtime to prevent gaming, the verifier computes
the exact ground truth directly from the agent's input file during verification.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant sub-99 is excluded/flagged              (25 pts)
  3. CE and AE metrics correct for ≥12 valid participants          (30 pts)
  4. CV metric correct for ≥12 valid participants                  (20 pts)
  5. Group means correctly aggregated from participant stats       (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import statistics
import csv

def verify_time_production_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Copy the report JSON
    report_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    report_tmp.close()
    
    report = {}
    try:
        copy_from_env('/home/ga/pebl/analysis/timing_report.json', report_tmp.name)
        with open(report_tmp.name, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback.append("[+10] Output file exists and is valid JSON.")
    except Exception as e:
        feedback.append(f"[0] Output file missing or invalid JSON: {e}")
        if os.path.exists(report_tmp.name):
            os.unlink(report_tmp.name)
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
    finally:
        if os.path.exists(report_tmp.name):
            os.unlink(report_tmp.name)

    # 2. Copy the dynamically generated dataset to compute ground truth
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    csv_tmp.close()
    try:
        copy_from_env('/home/ga/pebl/data/time_production_data.csv', csv_tmp.name)
        
        data = {}
        with open(csv_tmp.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                p = row['participant_id']
                t = int(row['target_duration_ms'])
                prod = int(row['produced_duration_ms'])
                
                if p not in data:
                    data[p] = {}
                if str(t) not in data[p]:
                    data[p][str(t)] = []
                data[p][str(t)].append(prod)
    except Exception as e:
        feedback.append(f"Error reading original data for verification: {e}")
        if os.path.exists(csv_tmp.name):
            os.unlink(csv_tmp.name)
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
    finally:
        if os.path.exists(csv_tmp.name):
            os.unlink(csv_tmp.name)

    # Calculate exact Ground Truth
    gt = {}
    for p, targets in data.items():
        gt[p] = {}
        for t_str, prods in targets.items():
            t = int(t_str)
            mean_prod = statistics.mean(prods)
            ce = statistics.mean([x - t for x in prods])
            ae = statistics.mean([abs(x - t) for x in prods])
            stdev = statistics.stdev(prods) if len(prods) > 1 else 0
            cv = stdev / mean_prod if mean_prod != 0 else 0
            gt[p][t_str] = {'ce': ce, 'ae': ae, 'cv': cv}
            
    valid_ppts = [p for p in gt.keys() if p != 'sub-99']
    
    # Calculate group means mathematically derived from valid participant means
    gt_group = {}
    for t_str in ['500', '1000', '2000', '3000']:
        gt_group[t_str] = {
            'mean_ce_ms': statistics.mean([gt[p][t_str]['ce'] for p in valid_ppts]),
            'mean_ae_ms': statistics.mean([gt[p][t_str]['ae'] for p in valid_ppts]),
            'mean_cv': statistics.mean([gt[p][t_str]['cv'] for p in valid_ppts])
        }

    # 3. Check Cheater Exclusion
    sub99_entry = next((item for item in report.get('participants', []) if item.get('id') == 'sub-99'), None)
    if sub99_entry and sub99_entry.get('excluded') in [True, 'true', 1, 'yes']:
        score += 25
        feedback.append("[+25] sub-99 correctly excluded/flagged.")
    elif not sub99_entry:
        score += 20
        feedback.append("[+20] sub-99 omitted from participants list (missing explicit exclusion flag, but functionally excluded).")
    else:
        feedback.append("[0] sub-99 not excluded.")

    # 4. Check Participant Metrics (CE/AE and CV separated for partial credit resilience)
    ce_ae_correct = 0
    cv_correct = 0
    
    for pid in valid_ppts:
        entry = next((item for item in report.get('participants', []) if item.get('id') == pid), None)
        if not entry:
            continue
            
        durations = entry.get('durations', {})
        ce_ae_ok = True
        cv_ok = True
        
        for t_str in ['500', '1000', '2000', '3000']:
            rdur = durations.get(t_str, {})
            gdur = gt[pid][t_str]
            try:
                if abs(float(rdur.get('ce_ms', 9999)) - gdur['ce']) > 1.5:
                    ce_ae_ok = False
                if abs(float(rdur.get('ae_ms', 9999)) - gdur['ae']) > 1.5:
                    ce_ae_ok = False
                if abs(float(rdur.get('cv', 9999)) - gdur['cv']) > 0.005:
                    cv_ok = False
            except (ValueError, TypeError):
                ce_ae_ok = False
                cv_ok = False
        
        if ce_ae_ok: ce_ae_correct += 1
        if cv_ok: cv_correct += 1
        
    if ce_ae_correct >= 12:
        score += 30
        feedback.append(f"[+30] Constant & Absolute Error correct for {ce_ae_correct}/15 participants.")
    elif ce_ae_correct >= 5:
        score += 15
        feedback.append(f"[+15] Constant & Absolute Error correct for {ce_ae_correct}/15 participants (partial).")
    else:
        feedback.append(f"[0] Constant & Absolute Error correct for only {ce_ae_correct}/15 participants.")
        
    if cv_correct >= 12:
        score += 20
        feedback.append(f"[+20] Coefficient of Variation correct for {cv_correct}/15 participants.")
    elif cv_correct >= 5:
        score += 10
        feedback.append(f"[+10] Coefficient of Variation correct for {cv_correct}/15 participants (partial).")
    else:
        feedback.append(f"[0] Coefficient of Variation correct for only {cv_correct}/15 participants.")

    # 5. Check Group Means
    report_group = report.get('group_means', {})
    correct_groups = 0
    for t_str in ['500', '1000', '2000', '3000']:
        rtg = report_group.get(t_str, {})
        gtg = gt_group[t_str]
        try:
            ce_ok = abs(float(rtg.get('mean_ce_ms', 9999)) - gtg['mean_ce_ms']) <= 1.5
            ae_ok = abs(float(rtg.get('mean_ae_ms', 9999)) - gtg['mean_ae_ms']) <= 1.5
            cv_ok = abs(float(rtg.get('mean_cv', 9999)) - gtg['mean_cv']) <= 0.005
            if ce_ok and ae_ok and cv_ok:
                correct_groups += 1
        except (ValueError, TypeError):
            pass
            
    if correct_groups == 4:
        score += 15
        feedback.append("[+15] Group means correct for all 4 durations.")
    elif correct_groups > 0:
        partial_score = int(15 * (correct_groups / 4))
        score += partial_score
        feedback.append(f"[+{partial_score}] Group means correct for {correct_groups}/4 durations.")
    else:
        feedback.append("[0] Group means incorrect or missing.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }