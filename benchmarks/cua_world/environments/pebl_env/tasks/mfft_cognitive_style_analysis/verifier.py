#!/usr/bin/env python3
"""
Verifier for mfft_cognitive_style_analysis task.

Scoring Logic (100 pts total):
  1. JSON Output Validity (10 pts)
  2. Contaminant (child-99) Exclusion (20 pts)
  3. Sample Medians Correct [derived from valid participants] (25 pts)
  4. Individual Classifications Correct (30 pts)
  5. Aggregate Counts match internal classifications (15 pts)

Pass Threshold: 65 pts + Medians Must Be Correct.
"""

import json
import os
import tempfile
import statistics
import random
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Replicate the exact data generation logic locally to produce robust ground truth.
# This ensures perfectly matched evaluations without relying on floating point artifacts.
def get_ground_truth():
    random.seed(42)
    valid_data = {}
    
    for i in range(1, 31):
        pid = f"child-{i:02d}"
        quad = i % 4
        if quad == 0:
            base_rt = 4000; base_err_prob = 0.1
        elif quad == 1:
            base_rt = 1500; base_err_prob = 0.6
        elif quad == 2:
            base_rt = 1500; base_err_prob = 0.1
        else:
            base_rt = 4000; base_err_prob = 0.6

        trials = []
        for t in range(1, 13):
            rt = max(500, random.gauss(base_rt, 500))
            err = 0
            while random.random() < base_err_prob and err < 5:
                err += 1
            trials.append((round(rt, 1), err))
        valid_data[pid] = trials

    metrics = {}
    for pid, trials in valid_data.items():
        mean_rt = sum(t[0] for t in trials) / 12.0
        tot_err = sum(t[1] for t in trials)
        metrics[pid] = {'mean_rt': mean_rt, 'tot_err': tot_err}

    median_rt = statistics.median([m['mean_rt'] for m in metrics.values()])
    median_err = statistics.median([m['tot_err'] for m in metrics.values()])

    for pid, m in metrics.items():
        if m['mean_rt'] >= median_rt and m['tot_err'] < median_err:
            cat = "Reflective"
        elif m['mean_rt'] < median_rt and m['tot_err'] >= median_err:
            cat = "Impulsive"
        elif m['mean_rt'] < median_rt and m['tot_err'] < median_err:
            cat = "Fast-Accurate"
        else:
            cat = "Slow-Inaccurate"
        m['style'] = cat

    return median_rt, median_err, metrics

def verify_mfft_cognitive_style_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Evaluation error: copy_from_env missing."}

    score = 0
    feedback_parts = []
    
    # Generate Ground Truth
    gt_med_rt, gt_med_err, gt_metrics = get_ground_truth()

    # --- Criterion 1: Output File Exists and is valid JSON (10 pts) ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/mfft_cognitive_styles.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Report valid JSON.')
    except Exception as e:
        feedback_parts.append(f'[0] Could not read report: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback_parts)}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    participants = report.get('participants', [])
    if not isinstance(participants, list):
        return {'passed': False, 'score': score, 'feedback': 'Invalid schema: "participants" missing or not a list.'}

    # Build quick lookup
    part_map = {}
    for p in participants:
        pid = p.get('id') or p.get('participant_id') or p.get('participant')
        if pid:
            part_map[str(pid)] = p

    # --- Criterion 2: Contaminant child-99 Exclusion (20 pts) ---
    c99 = part_map.get('child-99', {})
    if c99.get('excluded') in (True, 'true', 'yes', 1):
        score += 20
        feedback_parts.append('[+20] child-99 correctly excluded.')
    elif 'child-99' not in part_map:
        # Check if they put it in a separate list
        if 'child-99' in report.get('excluded', []):
            score += 20
            feedback_parts.append('[+20] child-99 correctly excluded.')
        else:
            feedback_parts.append('[0] child-99 not flagged as excluded.')
    else:
        feedback_parts.append('[0] child-99 present but not flagged as excluded.')

    # --- Criterion 3: Sample Medians Correct (25 pts) ---
    stats = report.get('sample_statistics', {})
    agent_med_rt = stats.get('median_first_rt_ms')
    agent_med_err = stats.get('median_total_errors')
    
    medians_correct = False
    if agent_med_rt is not None and agent_med_err is not None:
        try:
            rt_diff = abs(float(agent_med_rt) - gt_med_rt)
            err_diff = abs(float(agent_med_err) - gt_med_err)
            
            if rt_diff <= 0.5 and err_diff <= 0.1:
                score += 25
                medians_correct = True
                feedback_parts.append('[+25] Valid sample medians correct.')
            else:
                feedback_parts.append(f'[0] Medians incorrect (Expected RT: {gt_med_rt:.1f}, Err: {gt_med_err:.1f}).')
        except ValueError:
            feedback_parts.append('[0] Medians must be numeric.')
    else:
        feedback_parts.append('[0] sample_statistics missing from report.')

    # --- Criterion 4: Individual Classifications Correct (30 pts) ---
    correct_classes = 0
    agent_derived_counts = {"Reflective": 0, "Impulsive": 0, "Fast-Accurate": 0, "Slow-Inaccurate": 0}
    
    for pid, gt_data in gt_metrics.items():
        agent_p = part_map.get(pid, {})
        if agent_p and not agent_p.get('excluded'):
            agent_style = str(agent_p.get('cognitive_style', '')).strip()
            
            # Record for count checks
            if agent_style in agent_derived_counts:
                agent_derived_counts[agent_style] += 1
                
            if agent_style.lower() == gt_data['style'].lower():
                correct_classes += 1

    if correct_classes >= 28:
        score += 30
        feedback_parts.append(f'[+30] Individual classifications correct ({correct_classes}/30).')
    elif correct_classes >= 15:
        score += 15
        feedback_parts.append(f'[+15] Individual classifications partially correct ({correct_classes}/30).')
    else:
        feedback_parts.append(f'[0] Individual classifications mostly incorrect ({correct_classes}/30).')

    # --- Criterion 5: Aggregate Counts Match Classifications (15 pts) ---
    reported_counts = report.get('style_counts', {})
    counts_match = True
    for sty, expected_count in agent_derived_counts.items():
        if reported_counts.get(sty) != expected_count:
            counts_match = False
            
    if counts_match and sum(agent_derived_counts.values()) > 0:
        score += 15
        feedback_parts.append('[+15] Aggregate style counts match classifications.')
    else:
        feedback_parts.append('[0] style_counts do not match the assigned participants.')

    # Determine passing state
    passed = score >= 65 and medians_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }