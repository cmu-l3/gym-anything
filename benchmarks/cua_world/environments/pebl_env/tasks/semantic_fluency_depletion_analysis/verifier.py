#!/usr/bin/env python3
"""
Verifier for semantic_fluency_depletion_analysis task.

Dynamically computes the ground truth from the provided CSV and compares
it to the agent's output JSON to ensure data cleaning, temporal binning,
and exclusion logic are all accurately implemented.

Scoring (100 pts total):
  1. Valid JSON Output                                        (10 pts)
  2. Bot participant (sub-99) explicitly excluded             (20 pts)
  3. Correct total words/deduplication logic for valid ppts   (25 pts)
  4. Correct temporal binning (Q1-Q4) for valid ppts          (25 pts)
  5. Correct group means (within float tolerance)             (20 pts)
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_semantic_fluency_depletion_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    score = 0
    feedback_parts = []
    
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    json_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    csv_path = csv_tmp.name
    json_path = json_tmp.name
    csv_tmp.close()
    json_tmp.close()

    try:
        # Step 1: Copy files from the container environment
        try:
            copy_from_env('/home/ga/pebl/data/semantic_fluency_data.csv', csv_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve CSV data: {e}"}
            
        try:
            copy_from_env('/home/ga/pebl/analysis/fluency_report.json', json_path)
            with open(json_path, encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append("[+10] Output JSON found and valid.")
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Output file not found."}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Invalid JSON format: {e}"}
            
        # Step 2: Dynamically calculate Ground Truth from the actual CSV
        gt_data = {}
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                pid = row['participant']
                word = row['word_typed'].strip().lower()
                rt = int(row['rt_ms'])
                
                if pid not in gt_data:
                    gt_data[pid] = {'words': [], 'intervals': [], 'last_rt': 0}
                    
                gt_data[pid]['intervals'].append(rt - gt_data[pid]['last_rt'])
                gt_data[pid]['last_rt'] = rt
                
                if word == "":
                    continue
                
                # Deduplicate: Only append if word hasn't been used by this participant
                if word not in [w for w, _ in gt_data[pid]['words']]:
                    gt_data[pid]['words'].append((word, rt))
                    
        gt_stats = {}
        for pid, data in gt_data.items():
            words = data['words']
            # Bin into quartiles based on rt_ms
            q1 = sum(1 for w, rt in words if rt <= 15000)
            q2 = sum(1 for w, rt in words if 15000 < rt <= 30000)
            q3 = sum(1 for w, rt in words if 30000 < rt <= 45000)
            q4 = sum(1 for w, rt in words if 45000 < rt <= 60000)
            
            gt_stats[pid] = {
                'total': len(words),
                'Q1': q1, 'Q2': q2, 'Q3': q3, 'Q4': q4
            }
            
        gt_group = {'total': 0, 'Q1': 0, 'Q2': 0, 'Q3': 0, 'Q4': 0}
        valid_count = 0
        for pid, stats in gt_stats.items():
            if pid == 'sub-99': continue
            valid_count += 1
            gt_group['total'] += stats['total']
            gt_group['Q1'] += stats['Q1']
            gt_group['Q2'] += stats['Q2']
            gt_group['Q3'] += stats['Q3']
            gt_group['Q4'] += stats['Q4']
            
        for k in gt_group:
            gt_group[k] /= valid_count

        # Step 3: Evaluate Agent Report
        participants = report.get('participants', [])
        p_map = {str(p.get('id', p.get('participant', ''))): p for p in participants}
        
        # Check Bot Exclusion
        s99 = p_map.get('sub-99', {})
        excluded = s99.get('excluded', False)
        if 'sub-99' not in p_map or excluded in [True, 'true', 1, 'yes']:
            score += 20
            feedback_parts.append("[+20] Synthetic bot (sub-99) correctly excluded.")
        else:
            feedback_parts.append("[0] Synthetic bot (sub-99) not excluded.")
            
        # Check Deduplication and Temporal Quartiles for valid participants
        correct_counts = 0
        correct_quartiles = 0
        valid_pids = [p for p in gt_stats.keys() if p != 'sub-99']
        
        for pid in valid_pids:
            gt = gt_stats[pid]
            agent_p = p_map.get(pid, {})
            
            # Word Count / Deduplication check
            total = agent_p.get('total_valid_words', -1)
            if total == gt['total']:
                correct_counts += 1
                
            # Quartiles check
            q = agent_p.get('quartiles', {})
            aq1, aq2 = q.get('Q1', -1), q.get('Q2', -1)
            aq3, aq4 = q.get('Q3', -1), q.get('Q4', -1)
            if aq1 == gt['Q1'] and aq2 == gt['Q2'] and aq3 == gt['Q3'] and aq4 == gt['Q4']:
                correct_quartiles += 1
                
        # Proportional scoring for deduplication
        if correct_counts == len(valid_pids):
            score += 25
            feedback_parts.append(f"[+25] Deduplication and filtering correct for all {len(valid_pids)} valid participants.")
        elif correct_counts > 0:
            pts = int(25 * (correct_counts / len(valid_pids)))
            score += pts
            feedback_parts.append(f"[+{pts}] Deduplication correct for {correct_counts}/{len(valid_pids)} participants.")
        else:
            feedback_parts.append("[0] Deduplication logic incorrect.")
            
        # Proportional scoring for quartile binning
        if correct_quartiles == len(valid_pids):
            score += 25
            feedback_parts.append(f"[+25] Temporal quartiles correct for all {len(valid_pids)} valid participants.")
        elif correct_quartiles > 0:
            pts = int(25 * (correct_quartiles / len(valid_pids)))
            score += pts
            feedback_parts.append(f"[+{pts}] Temporal quartiles correct for {correct_quartiles}/{len(valid_pids)} participants.")
        else:
            feedback_parts.append("[0] Temporal quartiles incorrect.")
            
        # Check Group Means
        gm = report.get('group_means', {})
        gm_correct = 0
        checks = [
            (gm.get('total_valid_words', -1), gt_group['total']),
            (gm.get('Q1', -1), gt_group['Q1']),
            (gm.get('Q2', -1), gt_group['Q2']),
            (gm.get('Q3', -1), gt_group['Q3']),
            (gm.get('Q4', -1), gt_group['Q4'])
        ]
        
        for ag_val, gt_val in checks:
            try:
                if abs(float(ag_val) - gt_val) <= 0.15:
                    gm_correct += 1
            except (ValueError, TypeError):
                pass
                
        if gm_correct == 5:
            score += 20
            feedback_parts.append("[+20] All 5 group means are accurate.")
        elif gm_correct > 0:
            pts = gm_correct * 4
            score += pts
            feedback_parts.append(f"[+{pts}] {gm_correct}/5 group means are accurate.")
        else:
            feedback_parts.append("[0] Group means are incorrect or missing.")
            
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    finally:
        if os.path.exists(csv_path):
            os.unlink(csv_path)
        if os.path.exists(json_path):
            os.unlink(json_path)