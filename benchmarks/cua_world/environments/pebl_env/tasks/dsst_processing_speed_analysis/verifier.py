#!/usr/bin/env python3
"""
Verifier for dsst_processing_speed_analysis task.

Calculates the actual ground-truth metrics from the CSV file that was dynamically
generated during setup, and strictly compares the agent's calculations against it.

Scoring (100 pts total):
  1. Valid JSON format                                       (10 pts)
  2. Temporal cutoff logic applied correctly to scores       (20 pts)
  3. ILI correctly computed with proper null fallbacks       (20 pts)
  4. Accuracy outlier/artifact correctly excluded            (25 pts)
  5. Group statistics computed avoiding excluded data/nulls  (25 pts)

Pass Threshold: 65 pts.
"""

import json
import os
import tempfile
import csv

def safe_float(val):
    if val is None:
        return None
    if isinstance(val, str) and val.lower() == 'null':
        return None
    try:
        return float(val)
    except (ValueError, TypeError):
        return None

def verify_dsst_processing_speed_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    tmp_csv = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    tmp_json = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    
    try:
        copy_from_env('/home/ga/pebl/data/dsst_data.csv', tmp_csv.name)
        copy_from_env('/home/ga/pebl/analysis/dsst_report.json', tmp_json.name)
        
        if not os.path.exists(tmp_csv.name) or os.path.getsize(tmp_csv.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve dsst_data.csv from container"}
            
        # Programmatically calculate Ground Truth
        participants = {}
        with open(tmp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                pid = row['participant_id']
                if pid not in participants:
                    participants[pid] = []
                participants[pid].append({
                    'trial': int(row['trial']),
                    'elapsed': int(row['elapsed_time_ms']),
                    'rt': int(row['rt_ms']),
                    'correct': int(row['correct'])
                })
                
        results = {}
        for pid, trials in participants.items():
            # Apply strict temporal cutoff logic
            trials_90s = [t for t in trials if t['elapsed'] <= 90000]
            correct_90s = [t for t in trials_90s if t['correct'] == 1]
            
            score_90s = len(correct_90s)
            acc_rate = score_90s / len(trials_90s) if trials_90s else 0.0
            
            # Evaluate the ILI Edge case logic (nullify participants without sufficient stats to form means)
            if len(correct_90s) < 30:
                ili = None
            else:
                correct_90s.sort(key=lambda x: x['trial'])
                first_15 = sum(t['rt'] for t in correct_90s[:15]) / 15.0
                last_15 = sum(t['rt'] for t in correct_90s[-15:]) / 15.0
                ili = first_15 - last_15
                
            excluded = acc_rate < 0.20
            
            results[pid] = {
                'clinical_score_90s': score_90s,
                'accuracy_rate': acc_rate,
                'incidental_learning_ms': ili,
                'excluded': excluded
            }
            
        # Group logic
        valid_pids = [pid for pid, r in results.items() if not r['excluded']]
        gt_mean_score = sum(results[pid]['clinical_score_90s'] for pid in valid_pids) / len(valid_pids) if valid_pids else 0.0
        
        valid_ili_pids = [pid for pid in valid_pids if results[pid]['incidental_learning_ms'] is not None]
        gt_mean_learning = sum(results[pid]['incidental_learning_ms'] for pid in valid_ili_pids) / len(valid_ili_pids) if valid_ili_pids else 0.0

        if not os.path.exists(tmp_json.name) or os.path.getsize(tmp_json.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Output file /home/ga/pebl/analysis/dsst_report.json not found."}
            
        try:
            with open(tmp_json.name, 'r', encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append("[+10] Output file is valid JSON.")
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Output file is not valid JSON: {e}"}
            
        part_list = report.get('participants', [])
        agent_parts = {}
        for p in part_list:
            pid = p.get('id') or p.get('participant_id') or p.get('participant')
            if pid:
                agent_parts[pid] = p
                
        correct_scores = 0
        correct_ilis = 0
        
        # Crosscheck individual participants against ground truth logic
        for pid, gt in results.items():
            if pid not in agent_parts:
                continue
            ap = agent_parts[pid]
            
            if gt['excluded']:
                continue
            if ap.get('excluded') in (True, 'true', 1):
                continue
                
            ap_score = safe_float(ap.get('clinical_score_90s'))
            if ap_score is not None and abs(ap_score - gt['clinical_score_90s']) < 0.1:
                correct_scores += 1
                
            ap_ili = safe_float(ap.get('incidental_learning_ms'))
            if gt['incidental_learning_ms'] is None:
                if ap_ili is None:
                    correct_ilis += 1
            else:
                if ap_ili is not None and abs(ap_ili - gt['incidental_learning_ms']) < 2.0:
                    correct_ilis += 1
                        
        valid_count = len(valid_pids)
        if valid_count > 0:
            if correct_scores >= valid_count - 2:
                score += 20
                feedback_parts.append("[+20] Temporal cutoff applied correctly.")
            elif correct_scores > 0:
                partial = int(20 * (correct_scores / valid_count))
                score += partial
                feedback_parts.append(f"[+{partial}] Temporal cutoff partially correct ({correct_scores}/{valid_count}).")
            else:
                feedback_parts.append("[0] Temporal cutoff not applied correctly.")
                
            if correct_ilis >= valid_count - 2:
                score += 20
                feedback_parts.append("[+20] ILI edge-case logic correct.")
            elif correct_ilis > 0:
                partial = int(20 * (correct_ilis / valid_count))
                score += partial
                feedback_parts.append(f"[+{partial}] ILI logic partially correct ({correct_ilis}/{valid_count}).")
            else:
                feedback_parts.append("[0] ILI logic incorrect.")
                
        # Evaluate exclusion of random-responder artifact
        artifact_pids = [pid for pid, r in results.items() if r['excluded']]
        if artifact_pids:
            art_pid = artifact_pids[0]
            is_excluded = False
            
            if art_pid in agent_parts and agent_parts[art_pid].get('excluded') in (True, 'true', 1):
                is_excluded = True
            elif 'excluded' in report and isinstance(report['excluded'], list) and art_pid in report['excluded']:
                is_excluded = True
                
            if is_excluded:
                score += 25
                feedback_parts.append(f"[+25] Artifact participant {art_pid} excluded correctly.")
            else:
                feedback_parts.append("[0] Artifact participant not excluded.")
                
        # Group stats logic verification 
        ap_group_score = safe_float(report.get('group_mean_score'))
        ap_group_learning = safe_float(report.get('group_mean_learning_ms'))
        
        stats_correct = 0
        if ap_group_score is not None and abs(ap_group_score - gt_mean_score) < 0.5:
            stats_correct += 12.5
        if ap_group_learning is not None and abs(ap_group_learning - gt_mean_learning) < 0.5:
            stats_correct += 12.5
            
        score += int(stats_correct)
        if stats_correct == 25:
            feedback_parts.append("[+25] Group statistics correct.")
        elif stats_correct > 0:
            feedback_parts.append(f"[+{int(stats_correct)}] Group statistics partially correct.")
        else:
            feedback_parts.append("[0] Group statistics incorrect.")
            
    finally:
        for tmp in [tmp_csv, tmp_json]:
            try:
                if os.path.exists(tmp.name):
                    os.unlink(tmp.name)
            except Exception:
                pass
                
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }