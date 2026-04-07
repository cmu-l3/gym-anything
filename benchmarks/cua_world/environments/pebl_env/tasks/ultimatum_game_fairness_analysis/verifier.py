#!/usr/bin/env python3
"""
Verifier for Ultimatum Game Fairness Analysis task.

Evaluates the agent's report against dynamically computed ground truth 
derived straight from the generated CSV file.

Criteria:
1. Valid JSON Output (10 pts)
2. Corrupted Participant Excluded (20 pts)
3. Tier Acceptance Rates Correct (25 pts)
4. MAO Computation Correct (25 pts)
5. Group Means Correct (20 pts)
"""

import json
import os
import tempfile
import csv
from collections import defaultdict

def compute_ground_truth(csv_path):
    """Computes exact ground truth from the raw data."""
    data = defaultdict(lambda: {'offers': defaultdict(list)})
    
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            offer = int(row['offer_to_responder'])
            accepted = 1 if row['response'].strip().lower() == 'accept' else 0
            data[pid]['offers'][offer].append(accepted)
            
    results = {}
    valid_participants = []
    
    for pid, pdata in data.items():
        offers = pdata['offers']
        
        # Calculate tier rates
        unfair_trials = offers[1] + offers[2] + offers[3]
        fair_trials = offers[4] + offers[5]
        hyper_trials = offers[6] + offers[7] + offers[8] + offers[9]
        
        unfair_rate = sum(unfair_trials) / len(unfair_trials) if unfair_trials else 0
        fair_rate = sum(fair_trials) / len(fair_trials) if fair_trials else 0
        hyper_rate = sum(hyper_trials) / len(hyper_trials) if hyper_trials else 0
        
        # Calculate MAO
        mao = 10
        for amt in range(1, 10):
            trials = offers[amt]
            if trials and (sum(trials) / len(trials)) >= 0.5:
                mao = amt
                break
                
        # Exclusion rule
        excluded = hyper_rate < 0.8
        if not excluded:
            valid_participants.append(pid)
            
        results[pid] = {
            'unfair': unfair_rate,
            'fair': fair_rate,
            'hyper_fair': hyper_rate,
            'mao': mao,
            'excluded': excluded
        }
        
    # Calculate group means
    g_unfair = sum(results[p]['unfair'] for p in valid_participants) / len(valid_participants)
    g_fair = sum(results[p]['fair'] for p in valid_participants) / len(valid_participants)
    g_hyper = sum(results[p]['hyper_fair'] for p in valid_participants) / len(valid_participants)
    g_mao = sum(results[p]['mao'] for p in valid_participants) / len(valid_participants)
    
    group_means = {
        'unfair_acceptance': g_unfair,
        'fair_acceptance': g_fair,
        'hyper_fair_acceptance': g_hyper,
        'mean_mao': g_mao
    }
    
    return results, group_means

def verify_ultimatum_game(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve required files from environment
    with tempfile.TemporaryDirectory() as temp_dir:
        report_path = os.path.join(temp_dir, 'report.json')
        data_path = os.path.join(temp_dir, 'data.csv')
        start_time_path = os.path.join(temp_dir, 'start_time.txt')
        mtime_path = os.path.join(temp_dir, 'mtime.txt')
        
        try:
            copy_from_env('/home/ga/pebl/analysis/ultimatum_report.json', report_path)
            copy_from_env('/home/ga/pebl/data/ultimatum_data.csv', data_path)
            copy_from_env('/tmp/task_start_time.txt', start_time_path)
            copy_from_env('/tmp/report_mtime.txt', mtime_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve required files: {e}"}

        # Anti-gaming check: Make sure file was created during the task run
        try:
            with open(start_time_path, 'r') as f:
                start_time = int(f.read().strip())
            with open(mtime_path, 'r') as f:
                report_mtime = int(f.read().strip())
                
            if report_mtime > 0 and report_mtime < start_time:
                return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: Output file existed before task started."}
        except Exception:
            pass # Ignore if timestamps fail to parse
            
        # Parse JSON
        try:
            with open(report_path, 'r', encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append("[+10] Report is valid JSON")
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Report is not valid JSON."}
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Report file not found."}

        # Compute Ground Truth dynamically from the CSV 
        try:
            gt_parts, gt_means = compute_ground_truth(data_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to compute ground truth from data: {e}"}

        # Convert report array to dict mapping for easy lookup
        agent_parts = {}
        for p in report.get('participants', []):
            pid = p.get('id')
            if pid:
                agent_parts[pid] = p
                
        # 2. Check exclusion logic (sub-99 specifically)
        target_excluded = "sub-99"
        sub99_agent = agent_parts.get(target_excluded, {})
        is_excluded = sub99_agent.get('excluded') in [True, 'true', 'Yes', 1]
        
        if is_excluded:
            score += 20
            feedback_parts.append("[+20] Anomalous participant (sub-99) correctly excluded")
        else:
            feedback_parts.append("[0] Anomalous participant (sub-99) was not excluded")
            
        # 3. and 4. Check Rates and MAO for valid participants
        correct_rates_count = 0
        correct_mao_count = 0
        valid_pt_count = 0
        
        for pid, gt_data in gt_parts.items():
            if gt_data['excluded']:
                continue # Only assess computations on valid participants
                
            valid_pt_count += 1
            agent_data = agent_parts.get(pid, {})
            rates = agent_data.get('acceptance_rates', {})
            mao = agent_data.get('mao')
            
            # Check Rates (within +/- 0.05)
            try:
                if (abs(float(rates.get('unfair', -1)) - gt_data['unfair']) <= 0.05 and
                    abs(float(rates.get('fair', -1)) - gt_data['fair']) <= 0.05 and
                    abs(float(rates.get('hyper_fair', -1)) - gt_data['hyper_fair']) <= 0.05):
                    correct_rates_count += 1
            except (TypeError, ValueError):
                pass
                
            # Check MAO (Exact match expected for integers)
            try:
                if int(mao) == gt_data['mao']:
                    correct_mao_count += 1
            except (TypeError, ValueError):
                pass

        if valid_pt_count > 0:
            rates_ratio = correct_rates_count / valid_pt_count
            mao_ratio = correct_mao_count / valid_pt_count
            
            if rates_ratio >= 0.90:
                score += 25
                feedback_parts.append(f"[+25] Tier rates correct for {correct_rates_count}/{valid_pt_count} valid participants")
            elif rates_ratio >= 0.50:
                score += 12
                feedback_parts.append(f"[+12] Tier rates correct for {correct_rates_count}/{valid_pt_count} valid participants (Partial)")
            else:
                feedback_parts.append(f"[0] Tier rates correct for only {correct_rates_count}/{valid_pt_count} valid participants")
                
            if mao_ratio >= 0.90:
                score += 25
                feedback_parts.append(f"[+25] MAO correct for {correct_mao_count}/{valid_pt_count} valid participants")
            elif mao_ratio >= 0.50:
                score += 12
                feedback_parts.append(f"[+12] MAO correct for {correct_mao_count}/{valid_pt_count} valid participants (Partial)")
            else:
                feedback_parts.append(f"[0] MAO correct for only {correct_mao_count}/{valid_pt_count} valid participants")
        
        # 5. Check Group Means
        agent_means = report.get('group_means', {})
        means_correct = True
        for key in ['unfair_acceptance', 'fair_acceptance', 'hyper_fair_acceptance', 'mean_mao']:
            gt_val = gt_means[key]
            # Handle possible slight key naming differences in agent output gracefully
            agent_val = agent_means.get(key)
            if agent_val is None:
                # Fallbacks just in case
                if key == 'mean_mao': agent_val = agent_means.get('mao')
                else: agent_val = agent_means.get(key.replace('_acceptance', ''))
                
            try:
                if agent_val is None or abs(float(agent_val) - gt_val) > 0.05:
                    means_correct = False
            except (TypeError, ValueError):
                means_correct = False
                
        if means_correct:
            score += 20
            feedback_parts.append("[+20] Group means matched ground truth")
        else:
            feedback_parts.append("[0] Group means inaccurate (likely due to inclusion of sub-99 or bad math)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }