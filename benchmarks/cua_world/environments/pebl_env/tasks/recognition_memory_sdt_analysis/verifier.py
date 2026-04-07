#!/usr/bin/env python3
"""
Verifier for recognition_memory_sdt_analysis task.

Calculates dynamic ground truth directly from the agent's input file to ensure 
absolute accuracy regardless of whether the real dataset or fallback was used.

Scores:
- File exists & valid JSON (10 pts)
- File modified during task (anti-gaming) (5 pts)
- Contaminated participant excluded (15 pts)
- 14 real participants present (10 pts)
- Hit/Miss/FA/CR counts correct (15 pts)
- d-prime correct (20 pts)
- criterion correct (10 pts)
- group means correct (15 pts)
"""

import json
import os
import tempfile
import csv
import logging
from scipy.stats import norm
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_ground_truth(csv_path):
    """Dynamically compute exact ground truth SDT from the source data."""
    participants = {}
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in participants:
                participants[pid] = {'hits': 0, 'misses': 0, 'fas': 0, 'crs': 0}
            
            stype = row['stimulus_type'].upper()
            resp = row['response'].lower()
            
            if stype == 'OLD' and resp == 'old':
                participants[pid]['hits'] += 1
            elif stype == 'OLD' and resp == 'new':
                participants[pid]['misses'] += 1
            elif stype == 'NEW' and resp == 'old':
                participants[pid]['fas'] += 1
            elif stype == 'NEW' and resp == 'new':
                participants[pid]['crs'] += 1

    gt = {}
    valid_d_primes = []
    valid_criterions = []
    
    for pid, counts in participants.items():
        if pid == 'sub-99999':
            continue  # Exclude from group stats
            
        hits, misses = counts['hits'], counts['misses']
        fas, crs = counts['fas'], counts['crs']
        n_old = hits + misses
        n_new = fas + crs
        
        hr = hits / n_old if n_old > 0 else 0
        far = fas / n_new if n_new > 0 else 0
        
        # Log-linear correction
        if hr == 1.0 or hr == 0.0 or far == 1.0 or far == 0.0:
            hr = (hits + 0.5) / (n_old + 1)
            far = (fas + 0.5) / (n_new + 1)
            
        d_prime = norm.ppf(hr) - norm.ppf(far)
        criterion = -0.5 * (norm.ppf(hr) + norm.ppf(far))
        
        gt[pid] = {
            'hits': hits, 'misses': misses, 'fas': fas, 'crs': crs,
            'd_prime': d_prime, 'criterion': criterion
        }
        
        valid_d_primes.append(d_prime)
        valid_criterions.append(criterion)

    group_stats = {
        'mean_d_prime': float(np.mean(valid_d_primes)),
        'mean_criterion': float(np.mean(valid_criterions))
    }
    
    return gt, group_stats

def verify_sdt_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    score = 0
    feedback = []

    # 1. Pull export metadata
    meta_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name
    try:
        copy_from_env('/tmp/task_export.json', meta_tmp)
        with open(meta_tmp, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to read export metadata."}
    finally:
        if os.path.exists(meta_tmp): os.unlink(meta_tmp)

    if not export_meta.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file sdt_report.json not found."}

    # 2. Check Timestamps (Anti-Gaming)
    task_start = export_meta.get('task_start_time', 0)
    report_mtime = export_meta.get('report_mtime', 0)
    if report_mtime >= task_start:
        score += 5
        feedback.append("[+5] Report created/modified during task.")
    else:
        feedback.append("[0] Report was not modified during task (possible anti-gaming violation).")

    # 3. Read Report
    report_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name
    report = None
    try:
        copy_from_env('/home/ga/pebl/analysis/sdt_report.json', report_tmp)
        with open(report_tmp, 'r') as f:
            report = json.load(f)
        score += 10
        feedback.append("[+10] Report is valid JSON.")
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Report invalid JSON: {e}"}
    finally:
        if os.path.exists(report_tmp): os.unlink(report_tmp)

    # 4. Pull Source Data to compute Absolute Ground Truth
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False).name
    try:
        copy_from_env('/home/ga/pebl/data/recognition_memory_data.csv', csv_tmp)
        gt_participants, gt_group = compute_ground_truth(csv_tmp)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to compute ground truth: {e}"}
    finally:
        if os.path.exists(csv_tmp): os.unlink(csv_tmp)

    parts_list = report.get("participants", [])
    part_map = {}
    for p in parts_list:
        pid = p.get("id") or p.get("participant_id")
        if pid:
            part_map[pid] = p

    # 5. Check Contamination Exclusion
    s99 = part_map.get("sub-99999")
    if s99 and s99.get("excluded") in (True, "true"):
        score += 15
        feedback.append("[+15] sub-99999 correctly excluded.")
    elif "sub-99999" not in part_map:
        score += 15
        feedback.append("[+15] sub-99999 omitted from participants (acceptable exclusion).")
    else:
        feedback.append("[0] sub-99999 not excluded.")

    # 6. Check Presence of Real Participants
    valid_ids_found = [pid for pid in gt_participants.keys() if pid in part_map]
    if len(valid_ids_found) == 14:
        score += 10
        feedback.append("[+10] All 14 real participants present.")
    else:
        feedback.append(f"[0] Only {len(valid_ids_found)}/14 valid participants found.")

    # 7. Evaluate Metrics
    correct_counts = 0
    correct_dprime = 0
    correct_crit = 0

    for pid, gt_vals in gt_participants.items():
        if pid not in part_map:
            continue
        p_data = part_map[pid]
        
        # Check counts
        try:
            if (int(p_data.get('hits', -1)) == gt_vals['hits'] and
                int(p_data.get('false_alarms', -1)) == gt_vals['fas']):
                correct_counts += 1
        except (ValueError, TypeError):
            pass
            
        # Check d-prime
        try:
            dp = float(p_data.get('d_prime', -999))
            if abs(dp - gt_vals['d_prime']) <= 0.3:
                correct_dprime += 1
        except (ValueError, TypeError):
            pass
            
        # Check criterion
        try:
            c = float(p_data.get('criterion', -999))
            if abs(c - gt_vals['criterion']) <= 0.2:
                correct_crit += 1
        except (ValueError, TypeError):
            pass

    if correct_counts >= 10:
        score += 15
        feedback.append(f"[+15] Hit/FA counts correct for {correct_counts}/14 participants.")
    else:
        feedback.append(f"[0] Hit/FA counts correct for only {correct_counts}/14.")

    if correct_dprime >= 10:
        score += 20
        feedback.append(f"[+20] D-prime accurate for {correct_dprime}/14 participants.")
    else:
        feedback.append(f"[0] D-prime accurate for only {correct_dprime}/14.")

    if correct_crit >= 10:
        score += 10
        feedback.append(f"[+10] Criterion accurate for {correct_crit}/14 participants.")
    else:
        feedback.append(f"[0] Criterion accurate for only {correct_crit}/14.")

    # 8. Group Summary Check
    grp = report.get('group_summary', {})
    try:
        mean_dp = float(grp.get('mean_d_prime', -999))
        if abs(mean_dp - gt_group['mean_d_prime']) <= 0.2:
            score += 10
            feedback.append("[+10] Group mean d-prime accurate.")
        else:
            feedback.append(f"[0] Group mean d-prime inaccurate (Expected ~{gt_group['mean_d_prime']:.2f}, got {mean_dp}).")
            
        mean_c = float(grp.get('mean_criterion', -999))
        if abs(mean_c - gt_group['mean_criterion']) <= 0.15:
            score += 5
            feedback.append("[+5] Group mean criterion accurate.")
        else:
            feedback.append("[0] Group mean criterion inaccurate.")
    except (ValueError, TypeError):
        feedback.append("[0] Group summary metrics missing or invalid.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }