#!/usr/bin/env python3
"""
Verifier for the Gratton Conflict Adaptation Analysis task.

Scoring (100 pts total):
  - Output file exists, created during task, and is valid JSON (10 pts)
  - sub-999 correctly excluded (15 pts)
  - All 25 valid participants are included in the output (10 pts)
  - Cell means matching exactly indicates perfect row shifting & lag logic (25 pts)
  - Post-error logic strictly followed yielding exact Gratton effects (20 pts)
  - Group mean Gratton calculated correctly (20 pts)
"""

import json
import os
import csv
import tempfile
from collections import defaultdict
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_ground_truth(csv_path):
    """
    Dynamically computes the exact ground truth directly from the generated CSV.
    This ensures verifier robustness by strictly applying the exclusion rules.
    """
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        data = list(reader)

    # Group by participant and block
    parts = defaultdict(lambda: defaultdict(list))
    for row in data:
        parts[row['participant_id']][row['block']].append(row)

    gt = {}
    for pid, blocks in parts.items():
        if pid == 'sub-999':
            continue
            
        cells = {'cC': [], 'cI': [], 'iC': [], 'iI': []}
        for b, trials in blocks.items():
            trials.sort(key=lambda x: int(x['trial']))
            for i in range(1, len(trials)):
                curr = trials[i]
                prev = trials[i-1]
                
                # Rule: Current accurate, Prev accurate (no post-error)
                if int(curr['acc']) == 1 and int(prev['acc']) == 1:
                    cell = prev['congruency'] + curr['congruency']
                    cells[cell].append(float(curr['rt_ms']))

        means = {k: sum(v)/len(v) if v else 0.0 for k, v in cells.items()}
        gratton = (means['cI'] - means['cC']) - (means['iI'] - means['iC'])
        
        gt[pid] = {
            'rt_cC': means['cC'],
            'rt_cI': means['cI'],
            'rt_iC': means['iC'],
            'rt_iI': means['iI'],
            'gratton_effect': gratton
        }
        
    valid_grattons = [v['gratton_effect'] for v in gt.values()]
    group_mean = sum(valid_grattons) / len(valid_grattons) if valid_grattons else 0
    return gt, group_mean

def verify_gratton_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Paths in environment
    agent_json_path = "/home/ga/pebl/analysis/gratton_report.json"
    agent_csv_path = "/home/ga/pebl/data/simon_data.csv"
    export_stats_path = "/tmp/export_stats.json"

    # Temp files on host
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as t_json, \
         tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as t_csv, \
         tempfile.NamedTemporaryFile(suffix='.json', delete=False) as t_stats:
        
        host_json_path = t_json.name
        host_csv_path = t_csv.name
        host_stats_path = t_stats.name

    try:
        # Pull stats first for anti-gaming
        copy_from_env(export_stats_path, host_stats_path)
        with open(host_stats_path, 'r') as f:
            stats = json.load(f)
            
        if not stats.get("file_exists"):
            return {"passed": False, "score": 0, "feedback": "Failure: output JSON file not found."}
        if not stats.get("file_created_during_task"):
            feedback_parts.append("[0] File exists but was not modified/created during the task execution (Anti-gaming triggered).")
            return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

        # Pull report and CSV
        copy_from_env(agent_json_path, host_json_path)
        copy_from_env(agent_csv_path, host_csv_path)

        with open(host_json_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
            
        score += 10
        feedback_parts.append("[+10] File is valid JSON and created during task.")

        # Compute dynamic GT
        gt_data, gt_group_mean = compute_ground_truth(host_csv_path)

        participants_list = report.get('participants', [])
        part_map = {str(e.get('id', '')): e for e in participants_list if e.get('id')}

        # Check sub-999 exclusion
        s999 = part_map.get('sub-999')
        if s999 and s999.get('excluded') in (True, 'true', 1, 'yes'):
            score += 15
            feedback_parts.append("[+15] Artifact participant sub-999 correctly excluded.")
        elif 'sub-999' not in part_map:
            # If completely omitted but not documented as excluded, it's partially okay but violates output spec
            score += 10
            feedback_parts.append("[+10] Artifact participant sub-999 omitted, though missing exclusion documentation.")
        else:
            feedback_parts.append("[0] Artifact participant sub-999 was included instead of excluded.")

        # Check all 25 valid participants exist
        valid_keys = set(gt_data.keys())
        agent_keys = set(part_map.keys())
        matched_keys = valid_keys.intersection(agent_keys)
        
        if len(matched_keys) == 25:
            score += 10
            feedback_parts.append("[+10] All 25 valid participants included in report.")
        else:
            feedback_parts.append(f"[0] Expected 25 valid participants, found {len(matched_keys)}.")

        # Verify Cell Means and Gratton exactness (lag logic + post-error)
        cell_match_count = 0
        gratton_match_count = 0
        
        for pid in matched_keys:
            gt = gt_data[pid]
            agent = part_map[pid]
            
            try:
                # Check cells (lag shifting verification) - Tolerance 1.0 ms
                cells_ok = all(
                    abs(float(agent.get(k, 0)) - gt[k]) <= 1.0 
                    for k in ['rt_cC', 'rt_cI', 'rt_iC', 'rt_iI']
                )
                if cells_ok: cell_match_count += 1

                # Check Gratton (post-error dropping verification) - Tolerance 1.0
                grat_ok = abs(float(agent.get('gratton_effect', 0)) - gt['gratton_effect']) <= 1.0
                if grat_ok: gratton_match_count += 1
                
            except (TypeError, ValueError):
                pass
                
        if cell_match_count >= 20:
            score += 25
            feedback_parts.append(f"[+25] Cell means logic accurate for {cell_match_count}/25 participants.")
        else:
            feedback_parts.append(f"[0] Cell means logic accurate for only {cell_match_count}/25 participants.")
            
        if gratton_match_count >= 20:
            score += 20
            feedback_parts.append(f"[+20] Gratton effect (post-error logic) accurate for {gratton_match_count}/25 participants.")
        else:
            feedback_parts.append(f"[0] Gratton effect accurate for only {gratton_match_count}/25 participants.")

        # Check Group Mean
        agent_group_mean = report.get('group_mean_gratton')
        if agent_group_mean is not None:
            try:
                diff = abs(float(agent_group_mean) - gt_group_mean)
                if diff <= 0.5:
                    score += 20
                    feedback_parts.append(f"[+20] Group mean {float(agent_group_mean):.2f} matches GT {gt_group_mean:.2f}.")
                else:
                    feedback_parts.append(f"[0] Group mean {float(agent_group_mean):.2f} exceeds GT tolerance ({gt_group_mean:.2f}).")
            except (ValueError, TypeError):
                feedback_parts.append("[0] Group mean is not a valid float.")
        else:
            feedback_parts.append("[0] Missing 'group_mean_gratton' key.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error during verification: {str(e)}"}
    finally:
        for f in [host_json_path, host_csv_path, host_stats_path]:
            if os.path.exists(f):
                os.unlink(f)

    # Final pass logic
    passed = score >= 65 and cell_match_count >= 20
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }