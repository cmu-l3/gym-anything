#!/usr/bin/env python3
"""
Verifier for dotprobe_reliability_analysis task.

Calculates the exact ground truth dynamically from the provided CSV file
to guarantee 100% precision against whatever the setup script generated.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_ground_truth(csv_path):
    """Dynamically compute the exact ground truth from the raw dataset."""
    df = pd.read_csv(csv_path)
    
    # 1. Overall accuracy (including fillers)
    acc_df = df.groupby('participant_id')['correct'].mean()
    valid_pids = acc_df[acc_df >= 0.80].index.tolist()
    excluded_pids = acc_df[acc_df < 0.80].index.tolist()
    
    # 2. Filter target trials
    target_df = df[(df['congruency'] != 'filler') & 
                   (df['correct'] == 1) & 
                   (df['rt_ms'] >= 200) & 
                   (df['rt_ms'] <= 1000)].copy()
                   
    # Only valid participants
    target_df = target_df[target_df['participant_id'].isin(valid_pids)]
    
    # Calculate AB Scores
    def calc_ab(sub_df):
        cong = sub_df[sub_df['congruency'] == 'congruent']['rt_ms'].mean()
        incong = sub_df[sub_df['congruency'] == 'incongruent']['rt_ms'].mean()
        return incong - cong
        
    ab_total = target_df.groupby('participant_id').apply(calc_ab)
    ab_odd = target_df[target_df['trial_num'] % 2 != 0].groupby('participant_id').apply(calc_ab)
    ab_even = target_df[target_df['trial_num'] % 2 == 0].groupby('participant_id').apply(calc_ab)
    
    # Group Metrics
    mean_ab_score = ab_total.mean()
    
    align_df = pd.DataFrame({'odd': ab_odd, 'even': ab_even}).dropna()
    correlation_r = align_df['odd'].corr(align_df['even'])
    spearman_brown = (2 * correlation_r) / (1 + correlation_r)
    
    return {
        "valid_pids": valid_pids,
        "excluded_pids": excluded_pids,
        "ab_total": ab_total.to_dict(),
        "ab_odd": ab_odd.to_dict(),
        "ab_even": ab_even.to_dict(),
        "mean_ab_score": mean_ab_score,
        "split_half_correlation_r": correlation_r,
        "spearman_brown_reliability": spearman_brown
    }

def verify_dotprobe_reliability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Temporary files
    tmp_csv = tempfile.NamedTemporaryFile(suffix='.csv', delete=False).name
    tmp_json = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name
    tmp_meta = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name

    try:
        # Check if output file was generated
        try:
            copy_from_env("/tmp/task_export_meta.json", tmp_meta)
            with open(tmp_meta, 'r') as f:
                meta = json.load(f)
            if not meta.get("file_created_during_task", False):
                feedback_parts.append("Warning: Output file timestamp indicates it may have existed before the task.")
        except Exception:
            pass

        # Load raw data and compute Ground Truth
        try:
            copy_from_env("/home/ga/pebl/data/dotprobe_data.csv", tmp_csv)
            gt = compute_ground_truth(tmp_csv)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to calculate ground truth from CSV: {e}"}

        # Load Agent's JSON report
        try:
            copy_from_env("/home/ga/pebl/analysis/dotprobe_reliability.json", tmp_json)
            with open(tmp_json, 'r', encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append("[+10] Output JSON found and parsed.")
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Output JSON file not found."}
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Output file is not valid JSON: {e}"}

        # Extract agent's participants
        participants = report.get('participants', [])
        part_map = {str(p.get('id')): p for p in participants if 'id' in p}
        
        # Criterion: Excluded participant logic (20 pts)
        sub99 = part_map.get('sub-99', {})
        if sub99.get('excluded') in (True, 'true', 1):
            score += 20
            feedback_parts.append("[+20] Correctly excluded participant sub-99 due to low accuracy.")
        else:
            feedback_parts.append("[0] Did not correctly exclude sub-99.")
            
        # Criterion: Individual Total AB Scores (20 pts)
        correct_totals = 0
        correct_splits = 0
        total_valid = len(gt["valid_pids"])
        
        for pid in gt["valid_pids"]:
            agent_pt = part_map.get(pid, {})
            gt_tot = gt["ab_total"].get(pid, 0)
            gt_odd = gt["ab_odd"].get(pid, 0)
            gt_even = gt["ab_even"].get(pid, 0)
            
            # Check total AB
            ag_tot = agent_pt.get('ab_score_total')
            if ag_tot is not None and abs(float(ag_tot) - gt_tot) <= 0.5:
                correct_totals += 1
                
            # Check odd/even
            ag_odd = agent_pt.get('ab_score_odd')
            ag_even = agent_pt.get('ab_score_even')
            if ag_odd is not None and ag_even is not None:
                if abs(float(ag_odd) - gt_odd) <= 0.5 and abs(float(ag_even) - gt_even) <= 0.5:
                    correct_splits += 1

        if total_valid > 0:
            if correct_totals / total_valid >= 0.90:
                score += 20
                feedback_parts.append(f"[+20] Total AB scores accurate for {correct_totals}/{total_valid} participants.")
            elif correct_totals > 0:
                score += int(20 * (correct_totals / total_valid))
                feedback_parts.append(f"[Partial] Total AB scores accurate for {correct_totals}/{total_valid} participants.")
            else:
                feedback_parts.append("[0] Total AB scores incorrect.")

            # Criterion: Individual Odd/Even Splits (20 pts)
            if correct_splits / total_valid >= 0.90:
                score += 20
                feedback_parts.append(f"[+20] Odd/Even AB scores accurate for {correct_splits}/{total_valid} participants.")
            elif correct_splits > 0:
                score += int(20 * (correct_splits / total_valid))
                feedback_parts.append(f"[Partial] Odd/Even AB scores accurate for {correct_splits}/{total_valid} participants.")
            else:
                feedback_parts.append("[0] Odd/Even AB scores incorrect.")

        # Criterion: Group Reliability Math (30 pts)
        group = report.get('group_metrics', {})
        
        ag_mean = group.get('mean_ab_score')
        ag_r = group.get('split_half_correlation_r')
        ag_R = group.get('spearman_brown_reliability')
        
        math_score = 0
        if ag_mean is not None and abs(float(ag_mean) - gt["mean_ab_score"]) <= 0.5:
            math_score += 10
            feedback_parts.append("[+10] Group mean AB score correct.")
        
        if ag_r is not None and abs(float(ag_r) - gt["split_half_correlation_r"]) <= 0.05:
            math_score += 10
            feedback_parts.append("[+10] Split-half correlation (r) correct.")
            
        if ag_R is not None and abs(float(ag_R) - gt["spearman_brown_reliability"]) <= 0.05:
            math_score += 10
            feedback_parts.append("[+10] Spearman-Brown reliability correct.")
            
        if math_score == 0:
            feedback_parts.append("[0] Group metrics incorrect or missing.")
            
        score += math_score

        passed = score >= 60
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }

    finally:
        for p in [tmp_csv, tmp_json, tmp_meta]:
            if os.path.exists(p):
                os.unlink(p)