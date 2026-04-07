"""
Verifier for gng_inhibitory_control_analysis task.

Dynamically calculates exact ground truth directly from the agent's input file to
prevent hardcoded failures if the generation seed or script is ever altered.

Scoring (100 pts total):
  1. File Existence & Schema (10 pts)
  2. Contamination Detection (20 pts)
  3. Error Counts Accurate (20 pts)
  4. SDT Implementation (d') (25 pts)
  5. RT Calculation (10 pts)
  6. Group Aggregation (15 pts)
"""

import json
import os
import csv
import tempfile
import math

try:
    from scipy.stats import norm
except ImportError:
    import subprocess
    import sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy"])
    from scipy.stats import norm

def calculate_ground_truth(csv_path):
    """Calculates the absolute ground truth metrics direct from the data file."""
    ppts = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in ppts:
                ppts[pid] = {'go': 0, 'nogo': 0, 'hits': 0, 'fas': 0, 'hit_rts': [], 'omissions': 0, 'commissions': 0}

            is_go = (row['condition'] == 'GO')
            resp = int(row['response'])
            rt = float(row['rt_ms'])

            if is_go:
                ppts[pid]['go'] += 1
                if resp == 1:
                    ppts[pid]['hits'] += 1
                    ppts[pid]['hit_rts'].append(rt)
                else:
                    ppts[pid]['omissions'] += 1
            else:
                ppts[pid]['nogo'] += 1
                if resp == 1:
                    ppts[pid]['fas'] += 1
                    ppts[pid]['commissions'] += 1

    metrics = {}
    for pid, d in ppts.items():
        n_go = d['go']
        n_nogo = d['nogo']
        
        hr = d['hits'] / n_go if n_go > 0 else 0
        far = d['fas'] / n_nogo if n_nogo > 0 else 0
        hit_rt = sum(d['hit_rts']) / len(d['hit_rts']) if d['hit_rts'] else 0

        # Boundary correction
        if hr == 1: hr = (n_go - 0.5) / n_go
        if hr == 0: hr = 0.5 / n_go
        if far == 1: far = (n_nogo - 0.5) / n_nogo
        if far == 0: far = 0.5 / n_nogo

        dprime = norm.ppf(hr) - norm.ppf(far)
        excluded = (far >= 0.90 and hit_rt < 100)

        metrics[pid] = {
            'omission_errors': d['omissions'],
            'commission_errors': d['commissions'],
            'hit_rate': hr,
            'false_alarm_rate': far,
            'mean_hit_rt_ms': hit_rt,
            'd_prime': dprime,
            'excluded': excluded
        }
        
    valid_pids = [p for p in metrics if not metrics[p]['excluded']]
    group = {
        'omission_errors': sum(metrics[p]['omission_errors'] for p in valid_pids) / len(valid_pids),
        'commission_errors': sum(metrics[p]['commission_errors'] for p in valid_pids) / len(valid_pids),
        'mean_hit_rt_ms': sum(metrics[p]['mean_hit_rt_ms'] for p in valid_pids) / len(valid_pids),
        'hit_rate': sum(metrics[p]['hit_rate'] for p in valid_pids) / len(valid_pids),
        'false_alarm_rate': sum(metrics[p]['false_alarm_rate'] for p in valid_pids) / len(valid_pids),
        'd_prime': sum(metrics[p]['d_prime'] for p in valid_pids) / len(valid_pids)
    }

    return metrics, group


def verify_gng_inhibitory_control_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback = []

    # 1. Pull data for evaluation
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as json_tmp, \
         tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as csv_tmp:
        json_path = json_tmp.name
        csv_path = csv_tmp.name

    try:
        copy_from_env('/home/ga/pebl/data/gng_data.csv', csv_path)
        gt_metrics, gt_group = calculate_ground_truth(csv_path)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Failed to retrieve or parse source data: {e}'}

    try:
        copy_from_env('/home/ga/pebl/analysis/gng_report.json', json_path)
        with open(json_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback.append('[+10] Report valid JSON.')
    except FileNotFoundError:
        feedback.append('[0] Output report not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback)}
    except json.JSONDecodeError as e:
        feedback.append(f'[0] Invalid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback)}
    finally:
        os.unlink(json_path)
        os.unlink(csv_path)

    # Map participant answers
    participants = report.get('participants', [])
    ans_map = {str(p.get('id') or p.get('participant_id')): p for p in participants if 'id' in p or 'participant_id' in p}

    # 2. Exclusions (sub-99)
    s99 = ans_map.get('sub-99', {})
    if s99.get('excluded') in (True, 'true', 1):
        score += 20
        feedback.append('[+20] sub-99 correctly excluded.')
    else:
        # Check global exclusion array fallback
        exclusions = report.get('excluded', [])
        if 'sub-99' in exclusions:
            score += 20
            feedback.append('[+20] sub-99 correctly excluded.')
        else:
            feedback.append('[0] sub-99 not correctly excluded.')

    # Valid Ppts scoring setup
    valid_ppts = [pid for pid, d in gt_metrics.items() if not d['excluded']]
    n_valid = len(valid_ppts)
    correct_errs, correct_dprime, correct_rt = 0, 0, 0

    for pid in valid_ppts:
        ans = ans_map.get(pid, {})
        gt = gt_metrics[pid]

        if ans.get('excluded'): continue

        try:
            # 3. Error Counts
            if int(ans.get('omission_errors', -1)) == gt['omission_errors'] and \
               int(ans.get('commission_errors', -1)) == gt['commission_errors']:
                correct_errs += 1
            
            # 4. d-prime
            if ans.get('d_prime') is not None and abs(float(ans['d_prime']) - gt['d_prime']) < 0.05:
                correct_dprime += 1
            
            # 5. RT
            if ans.get('mean_hit_rt_ms') is not None and abs(float(ans['mean_hit_rt_ms']) - gt['mean_hit_rt_ms']) < 1.0:
                correct_rt += 1
        except (ValueError, TypeError):
            pass

    # Assign relative scoring
    err_score = int((correct_errs / n_valid) * 20)
    score += err_score
    feedback.append(f'[+{err_score}] Error counts correct for {correct_errs}/{n_valid} ppts.')

    dprime_score = int((correct_dprime / n_valid) * 25)
    score += dprime_score
    feedback.append(f'[+{dprime_score}] SDT/d-prime correct for {correct_dprime}/{n_valid} ppts.')

    rt_score = int((correct_rt / n_valid) * 10)
    score += rt_score
    feedback.append(f'[+{rt_score}] Hit RT correct for {correct_rt}/{n_valid} ppts.')

    # 6. Group Aggregation
    group = report.get('group_means', {})
    group_score = 0
    try:
        if group:
            if abs(float(group.get('d_prime', -99)) - gt_group['d_prime']) < 0.05: group_score += 5
            if abs(float(group.get('omission_errors', -99)) - gt_group['omission_errors']) < 0.5: group_score += 5
            if abs(float(group.get('mean_hit_rt_ms', -99)) - gt_group['mean_hit_rt_ms']) < 2.0: group_score += 5
    except (ValueError, TypeError):
        pass

    score += group_score
    feedback.append(f'[+{group_score}] Group aggregations accurate.')

    passed = score >= 60
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback)
    }