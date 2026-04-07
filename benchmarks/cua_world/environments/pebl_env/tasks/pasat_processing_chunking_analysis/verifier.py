#!/usr/bin/env python3
"""
Verifier for pasat_processing_chunking_analysis.

Robust Verification Strategy:
1. Valid JSON Report & Schema Check (10 pts)
2. Anti-Gaming Timestamp Check (15 pts) - Ensures report was built dynamically
3. VLM Trajectory Check (15 pts) - Ensures actual data analysis work was performed
4. Contamination Exclusion (15 pts) - Excludes sub-999 correctly
5. Streak Logic & Error Typologies (25 pts) - Checks longest_streak and acc categories
6. Group Means Calculation (20 pts) - Checks aggregation logic accuracy

Calculates ground truth *dynamically* from the very CSV the agent processed, 
eliminating hardcoded float discrepancies.
"""

import json
import os
import tempfile
import csv
from collections import defaultdict

# Gym-anything VLM imports
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
try:
    from vlm_utils import sample_trajectory_frames, query_vlm
except ImportError:
    pass  # Handle gracefully if unavailable in some test rigs

CONTAMINATED_ID = "sub-999"
CONDITIONS = ["3.0", "2.4", "2.0", "1.6"]

def calculate_ground_truth(csv_path):
    """Dynamically recalculates ground truth from the CSV to ensure perfect scoring accuracy."""
    participants = defaultdict(lambda: defaultdict(list))
    
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            isi = row['isi_condition']
            participants[pid][isi].append({
                'acc': int(row['accuracy']),
                'rt': float(row['rt_ms'])
            })
            
    gt_metrics = {}
    group_aggregates = {isi: {'correct': [], 'omission': [], 'commission': [], 'streak': [], 'rt': []} for isi in CONDITIONS}
    
    for pid, conds in participants.items():
        if pid == CONTAMINATED_ID:
            continue # Exclude
            
        gt_metrics[pid] = {}
        for isi in CONDITIONS:
            trials = conds[isi]
            correct_total = sum(1 for t in trials if t['acc'] == 1)
            omission_total = sum(1 for t in trials if t['acc'] == -1)
            commission_total = sum(1 for t in trials if t['acc'] == 0)
            
            # Longest streak logic
            max_streak = 0
            curr_streak = 0
            for t in trials:
                if t['acc'] == 1:
                    curr_streak += 1
                    max_streak = max(max_streak, curr_streak)
                else:
                    curr_streak = 0
                    
            correct_rts = [t['rt'] for t in trials if t['acc'] == 1]
            mean_rt = sum(correct_rts) / len(correct_rts) if correct_rts else 0.0
            
            gt_metrics[pid][isi] = {
                "correct_total": correct_total,
                "omission_total": omission_total,
                "commission_total": commission_total,
                "longest_streak": max_streak,
                "mean_rt_correct_ms": mean_rt
            }
            
            group_aggregates[isi]['correct'].append(correct_total)
            group_aggregates[isi]['omission'].append(omission_total)
            group_aggregates[isi]['commission'].append(commission_total)
            group_aggregates[isi]['streak'].append(max_streak)
            group_aggregates[isi]['rt'].append(mean_rt)
            
    # Calculate means
    group_means = {}
    for isi in CONDITIONS:
        n = len(group_aggregates[isi]['correct'])
        if n == 0: continue
        group_means[isi] = {
            "mean_correct": sum(group_aggregates[isi]['correct']) / n,
            "mean_omission": sum(group_aggregates[isi]['omission']) / n,
            "mean_commission": sum(group_aggregates[isi]['commission']) / n,
            "mean_longest_streak": sum(group_aggregates[isi]['streak']) / n,
            "mean_rt_correct_ms": sum(group_aggregates[isi]['rt']) / n
        }
        
    return gt_metrics, group_means

def verify_pasat_chunking_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Load Meta Data & File Check
    meta_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env("/tmp/task_result.json", meta_tmp.name)
        with open(meta_tmp.name, 'r') as f:
            export_meta = json.load(f)
            
        if not export_meta.get('report_exists'):
            return {"passed": False, "score": 0, "feedback": "Failure: Target report pasat_report.json not found."}
            
        # Anti-gaming timestamp check
        if export_meta.get('report_created_during_task'):
            score += 15
            feedback.append("[+15] Anti-Gaming: Report dynamically generated during task.")
        else:
            feedback.append("[0] Warning: Report file is older than task start. Possible gaming.")
            
        copy_from_env("/tmp/agent_report.json", report_tmp.name)
        with open(report_tmp.name, 'r') as f:
            report_data = json.load(f)
            
        score += 10
        feedback.append("[+10] Output file exists and parses as valid JSON.")
        
        copy_from_env("/tmp/pasat_data.csv", csv_tmp.name)
        gt_metrics, gt_group_means = calculate_ground_truth(csv_tmp.name)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading files: {str(e)}"}
    finally:
        for tmp in [meta_tmp, report_tmp, csv_tmp]:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 2. VLM Trajectory Check (Proof of Work)
    try:
        frames = sample_trajectory_frames(trajectory, n=4)
        vlm_prompt = """Review these desktop screenshots taken chronologically. 
Did the user write/run code (like Python, R, or shell commands) to analyze data?
Respond strictly in JSON: {"wrote_and_ran_code": true/false}"""
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("wrote_and_ran_code"):
            score += 15
            feedback.append("[+15] VLM: Trajectory verifies code writing and execution.")
        else:
            feedback.append("[0] VLM: No visual evidence of data analysis in trajectory.")
    except Exception as e:
        feedback.append(f"[0] VLM Exception: {e}")

    # 3. Contamination Exclusion Check
    participants_list = report_data.get('participants', [])
    s999_excluded = False
    valid_agent_ppts = {}
    
    for p in participants_list:
        pid = p.get('id')
        if pid == CONTAMINATED_ID:
            if p.get('excluded') in [True, "true", "True"]:
                s999_excluded = True
        elif not p.get('excluded'):
            valid_agent_ppts[pid] = p

    if s999_excluded:
        score += 15
        feedback.append("[+15] Quality Control: Corrupted participant sub-999 correctly identified and excluded.")
    else:
        feedback.append("[0] Quality Control: Failed to exclude biologically impossible sub-999 data.")

    # 4. Streak Logic & Error Typologies
    # Check 3 randomly selected participants to verify the logic works (no hardcoding)
    logic_correct = True
    samples_checked = 0
    for pid in list(gt_metrics.keys())[:3]:
        if pid in valid_agent_ppts:
            conds = valid_agent_ppts[pid].get('conditions', {})
            gt_conds = gt_metrics[pid]
            
            for isi in CONDITIONS:
                if isi not in conds:
                    logic_correct = False; break
                
                agt = conds[isi]
                gtt = gt_conds[isi]
                
                # Check specifics
                if (agt.get('longest_streak') != gtt['longest_streak'] or 
                    agt.get('omission_total') != gtt['omission_total'] or
                    agt.get('commission_total') != gtt['commission_total']):
                    logic_correct = False
            samples_checked += 1
            
    if logic_correct and samples_checked == 3:
        score += 25
        feedback.append("[+25] Data Logic: Streak counting and omission/commission typologies correctly applied.")
    else:
        feedback.append("[0] Data Logic: Incorrect longest_streak counting or error type summation.")

    # 5. Group Means Verification
    agent_means = report_data.get('group_means', {})
    means_passed = 0
    
    for isi in CONDITIONS:
        agt_isi = agent_means.get(isi, {})
        gtt_isi = gt_group_means.get(isi, {})
        
        if not agt_isi or not gtt_isi: continue
        
        # Validate against ground truth with 0.1 tolerance (float handling)
        check1 = abs(agt_isi.get('mean_longest_streak', 0) - gtt_isi['mean_longest_streak']) < 0.1
        check2 = abs(agt_isi.get('mean_omission', 0) - gtt_isi['mean_omission']) < 0.1
        check3 = abs(agt_isi.get('mean_rt_correct_ms', 0) - gtt_isi['mean_rt_correct_ms']) < 1.0
        
        if check1 and check2 and check3:
            means_passed += 1

    if means_passed == 4:
        score += 20
        feedback.append("[+20] Group Means: Aggregations match ground truth across all 4 conditions.")
    elif means_passed > 0:
        score += 10
        feedback.append(f"[+10] Group Means: Partial match ({means_passed}/4 conditions).")
    else:
        feedback.append("[0] Group Means: Aggregations do not match ground truth (did you include sub-999?).")

    # Determine Pass/Fail
    key_criteria_met = s999_excluded and logic_correct
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }