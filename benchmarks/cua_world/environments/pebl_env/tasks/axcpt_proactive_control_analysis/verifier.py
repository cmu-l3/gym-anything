#!/usr/bin/env python3
"""
Verifier for axcpt_proactive_control_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Exclusion Check (sub-999 successfully flagged)                (20 pts)
  3. Log-Linear d'-context calculation within tolerance            (25 pts)
  4. Conditional PBI-RT calculation within tolerance               (25 pts)
  5. Group Means reflect exact calculation & exclusions            (20 pts)

Pass threshold: 65 pts.
"""

import json
import os
import tempfile
import pandas as pd
import scipy.stats
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants and tolerances
CONTAMINATED_PARTICIPANT = 'sub-999'
D_PRIME_TOLERANCE = 0.015
PBI_RT_TOLERANCE = 0.005
GROUP_TOLERANCE = 0.05
PASS_THRESHOLD = 65


def compute_ground_truth(csv_path):
    """Computes the exact ground truth dynamically from the provided CSV file."""
    df = pd.read_csv(csv_path)
    gt_metrics = {}
    
    for pid in df['participant_id'].unique():
        sub_df = df[df['participant_id'] == pid]
        
        # Determine rates
        ax_trials = sub_df[(sub_df['cue'] == 'A') & (sub_df['probe'] == 'X')]
        ax_hits = ax_trials[ax_trials['response'] == 'target']
        
        bx_trials = sub_df[(sub_df['cue'] == 'B') & (sub_df['probe'] == 'X')]
        bx_fas = bx_trials[bx_trials['response'] == 'target']
        
        # 1. Uncorrected Exclusion Check
        ax_hit_rate_uncorrected = len(ax_hits) / len(ax_trials) if len(ax_trials) > 0 else 0
        if ax_hit_rate_uncorrected < 0.60:
            gt_metrics[pid] = {'excluded': True}
            continue
            
        # 2. Log-linear d'-context
        ax_hit_adj = (len(ax_hits) + 0.5) / (len(ax_trials) + 1)
        bx_fa_adj = (len(bx_fas) + 0.5) / (len(bx_trials) + 1)
        d_prime_context = scipy.stats.norm.ppf(ax_hit_adj) - scipy.stats.norm.ppf(bx_fa_adj)
        
        # 3. PBI-RT (Correct trials only)
        ay_trials = sub_df[(sub_df['cue'] == 'A') & (sub_df['probe'] == 'Y')]
        ay_correct = ay_trials[ay_trials['response'] == 'nontarget']
        bx_correct = bx_trials[bx_trials['response'] == 'nontarget']
        
        ay_rt = ay_correct['rt_ms'].mean() if len(ay_correct) > 0 else 0
        bx_rt = bx_correct['rt_ms'].mean() if len(bx_correct) > 0 else 0
        
        if (ay_rt + bx_rt) > 0:
            pbi_rt = (ay_rt - bx_rt) / (ay_rt + bx_rt)
        else:
            pbi_rt = 0.0
            
        gt_metrics[pid] = {
            'excluded': False,
            'd_prime_context': d_prime_context,
            'pbi_rt': pbi_rt
        }
        
    # Compute group means
    valid_d_primes = [m['d_prime_context'] for m in gt_metrics.values() if not m['excluded']]
    valid_pbi_rts = [m['pbi_rt'] for m in gt_metrics.values() if not m['excluded']]
    
    gt_group_means = {
        'group_mean_d_prime_context': sum(valid_d_primes) / len(valid_d_primes) if valid_d_primes else 0,
        'group_mean_pbi_rt': sum(valid_pbi_rts) / len(valid_pbi_rts) if valid_pbi_rts else 0
    }
    
    return gt_metrics, gt_group_means


def verify_axcpt_proactive_control_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env missing"}
        
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Copy data file to dynamically calculate Ground Truth
    # ---------------------------------------------------------
    gt_metrics = {}
    gt_group_means = {}
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        csv_path = tmp_csv.name
        
    try:
        copy_from_env('/home/ga/pebl/data/axcpt_data.csv', csv_path)
        gt_metrics, gt_group_means = compute_ground_truth(csv_path)
    except Exception as e:
        logger.error(f"Failed to calculate ground truth: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read internal ground truth data."}
    finally:
        os.unlink(csv_path)

    # ---------------------------------------------------------
    # Criterion 1: Output file exists and is valid JSON
    # ---------------------------------------------------------
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json:
        json_path = tmp_json.name

    try:
        copy_from_env('/home/ga/pebl/analysis/axcpt_report.json', json_path)
        with open(json_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/axcpt_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file invalid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        try:
            os.unlink(json_path)
        except Exception:
            pass

    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = (entry.get('id') or entry.get('participant_id') or entry.get('participant'))
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and pid in excluded_list:
            return True
        return False

    # ---------------------------------------------------------
    # Criterion 2: sub-999 correctly excluded
    # ---------------------------------------------------------
    if is_excluded(CONTAMINATED_PARTICIPANT):
        score += 20
        feedback_parts.append('[+20] Participant sub-999 correctly excluded based on accuracy constraint.')
    else:
        feedback_parts.append('[0] sub-999 not excluded despite AX Hit Rate falling below 0.60.')

    # ---------------------------------------------------------
    # Criterion 3 & 4: Log-Linear d'-context and PBI-RT precision
    # ---------------------------------------------------------
    d_prime_correct = 0
    pbi_rt_correct = 0
    valid_ppts = [pid for pid, mt in gt_metrics.items() if not mt['excluded']]
    
    for pid in valid_ppts:
        entry = part_map.get(pid, {})
        
        # d'-context eval
        agent_dprime = entry.get('d_prime_context') or entry.get('dprime_context') or entry.get('d_prime')
        if agent_dprime is not None:
            try:
                if abs(float(agent_dprime) - gt_metrics[pid]['d_prime_context']) <= D_PRIME_TOLERANCE:
                    d_prime_correct += 1
            except (ValueError, TypeError):
                pass
                
        # PBI-RT eval
        agent_pbi = entry.get('pbi_rt') or entry.get('pbi')
        if agent_pbi is not None:
            try:
                if abs(float(agent_pbi) - gt_metrics[pid]['pbi_rt']) <= PBI_RT_TOLERANCE:
                    pbi_rt_correct += 1
            except (ValueError, TypeError):
                pass

    n_valid = len(valid_ppts)
    if d_prime_correct >= (n_valid * 0.9):
        score += 25
        feedback_parts.append(f'[+25] d\'-context correct for {d_prime_correct}/{n_valid} valid subjects (Log-linear applied successfully).')
    else:
        feedback_parts.append(f'[0] d\'-context correct for only {d_prime_correct}/{n_valid} valid subjects.')

    if pbi_rt_correct >= (n_valid * 0.9):
        score += 25
        feedback_parts.append(f'[+25] PBI-RT correct for {pbi_rt_correct}/{n_valid} valid subjects (Correct trials filtered successfully).')
    else:
        feedback_parts.append(f'[0] PBI-RT correct for only {pbi_rt_correct}/{n_valid} valid subjects.')

    # ---------------------------------------------------------
    # Criterion 5: Group Means calculation
    # ---------------------------------------------------------
    agent_group_dprime = report.get('group_mean_d_prime_context')
    agent_group_pbi = report.get('group_mean_pbi_rt')
    group_score = 0
    
    if agent_group_dprime is not None:
        try:
            if abs(float(agent_group_dprime) - gt_group_means['group_mean_d_prime_context']) <= GROUP_TOLERANCE:
                group_score += 10
        except (ValueError, TypeError):
            pass

    if agent_group_pbi is not None:
        try:
            if abs(float(agent_group_pbi) - gt_group_means['group_mean_pbi_rt']) <= GROUP_TOLERANCE:
                group_score += 10
        except (ValueError, TypeError):
            pass
            
    score += group_score
    feedback_parts.append(f'[+{group_score}] Group means evaluation (expected exact exclusion handling).')

    passed = score >= PASS_THRESHOLD
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }