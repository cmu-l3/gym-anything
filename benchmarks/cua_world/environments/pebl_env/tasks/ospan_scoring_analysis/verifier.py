#!/usr/bin/env python3
"""
Verifier for ospan_scoring_analysis task.

This verifier robustly calculates the exact Ground Truth from the same CSV 
the agent uses. This guarantees that any changes to the data generation script 
are automatically accounted for and prevents hardcoded gaming.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Participants with math accuracy < 0.85 excluded (e.g. sub-99) (25 pts)
  3. Absolute Span correctly calculated (≥80% of valid subjects)   (20 pts)
  4. Partial Span correctly calculated (≥80% of valid subjects)    (25 pts)
  5. Group means correctly aggregated from valid participants      (20 pts)

Pass threshold: 60 pts
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXCLUSION_THRESHOLD = 0.85
PASS_THRESHOLD = 60

def compute_ground_truth(csv_path):
    """Programmatically compute the absolute ground truth from the raw data."""
    participants = {}
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in participants:
                participants[pid] = {
                    'math_correct': 0, 'math_attempted': 0,
                    'absolute_span': 0, 'partial_span': 0
                }
            
            p = participants[pid]
            p['math_correct'] += int(row['math_correct'])
            p['math_attempted'] += int(row['math_attempted'])
            
            set_size = int(row['set_size'])
            presented = row['letters_presented'].strip()
            # Clean recalled string as per task instructions
            recalled = row['letters_recalled'].replace(" ", "").upper()
            
            # Absolute Span Logic
            if presented == recalled:
                p['absolute_span'] += set_size
                
            # Partial Span Logic (strict serial position alignment)
            partial_score = sum(1 for a, b in zip(presented, recalled) if a == b)
            p['partial_span'] += partial_score

    # Finalize GT formatting and compute group means
    gt = {}
    valid_abs_spans = []
    valid_partial_spans = []
    
    for pid, data in participants.items():
        math_acc = data['math_correct'] / data['math_attempted'] if data['math_attempted'] > 0 else 0.0
        is_excluded = math_acc < EXCLUSION_THRESHOLD
        
        gt[pid] = {
            'math_accuracy': math_acc,
            'absolute_span': data['absolute_span'],
            'partial_span': data['partial_span'],
            'excluded': is_excluded
        }
        
        if not is_excluded:
            valid_abs_spans.append(data['absolute_span'])
            valid_partial_spans.append(data['partial_span'])
            
    gt_group_abs = sum(valid_abs_spans) / len(valid_abs_spans) if valid_abs_spans else 0
    gt_group_partial = sum(valid_partial_spans) / len(valid_partial_spans) if valid_partial_spans else 0
    
    return gt, gt_group_abs, gt_group_partial


def verify_ospan_scoring(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'Environment copy function missing.'}

    score = 0
    feedback_parts = []

    with tempfile.TemporaryDirectory() as temp_dir:
        csv_path = os.path.join(temp_dir, 'ospan_data.csv')
        report_path = os.path.join(temp_dir, 'ospan_report.json')

        # Extract files from environment
        try:
            copy_from_env('/home/ga/pebl/data/ospan_data.csv', csv_path)
        except Exception as e:
            return {'passed': False, 'score': 0, 'feedback': f"Failed to retrieve CSV data: {e}"}

        try:
            copy_from_env('/home/ga/pebl/analysis/ospan_report.json', report_path)
        except FileNotFoundError:
            return {'passed': False, 'score': 0, 'feedback': 'Output file ~/pebl/analysis/ospan_report.json not found.'}

        # --- Criterion 1: Output exists & valid JSON (10 pts) ---
        try:
            with open(report_path, encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append('[+10] Output file is valid JSON.')
        except (json.JSONDecodeError, ValueError) as e:
            return {'passed': False, 'score': 0, 'feedback': f'Output file not valid JSON: {e}'}

        # Compute Ground Truth dynamically from the container's CSV
        gt, gt_group_abs, gt_group_partial = compute_ground_truth(csv_path)

        # Parse agent report
        agent_participants = report.get('participants', [])
        agent_map = {}
        for entry in agent_participants:
            pid = entry.get('id') or entry.get('participant_id')
            if pid:
                agent_map[pid] = entry

        def agent_excluded(pid):
            entry = agent_map.get(pid, {})
            return entry.get('excluded') in (True, 'true', 1, 'yes')

        # --- Criterion 2: Threshold Exclusion (25 pts) ---
        correct_exclusions = 0
        total_exclusions_needed = sum(1 for data in gt.values() if data['excluded'])
        false_exclusions = 0

        for pid, data in gt.items():
            if data['excluded'] and agent_excluded(pid):
                correct_exclusions += 1
            elif not data['excluded'] and agent_excluded(pid):
                false_exclusions += 1

        if total_exclusions_needed > 0 and correct_exclusions == total_exclusions_needed and false_exclusions == 0:
            score += 25
            feedback_parts.append('[+25] Threshold exclusions (Math Accuracy < 0.85) applied perfectly.')
        elif correct_exclusions > 0:
            score += 10
            feedback_parts.append(f'[+10] Partial exclusion logic ({correct_exclusions}/{total_exclusions_needed} excluded, {false_exclusions} falsely excluded).')
        else:
            feedback_parts.append(f'[0] Exclusions failed (Expected {total_exclusions_needed} exclusions).')

        # --- Criteria 3 & 4: Absolute and Partial Spans (20 pts / 25 pts) ---
        correct_abs = 0
        correct_partial = 0
        valid_count = sum(1 for data in gt.values() if not data['excluded'])

        for pid, gt_data in gt.items():
            if gt_data['excluded']:
                continue
            
            agent_data = agent_map.get(pid, {})
            # Allow forgiving key names
            ag_abs = agent_data.get('absolute_span') or agent_data.get('abs_span')
            ag_partial = agent_data.get('partial_span') or agent_data.get('part_span')

            if ag_abs is not None and abs(float(ag_abs) - gt_data['absolute_span']) < 0.1:
                correct_abs += 1
            if ag_partial is not None and abs(float(ag_partial) - gt_data['partial_span']) < 0.1:
                correct_partial += 1

        if valid_count > 0:
            abs_ratio = correct_abs / valid_count
            if abs_ratio >= 0.95:
                score += 20
                feedback_parts.append(f'[+20] Absolute Span correct for {correct_abs}/{valid_count} valid participants.')
            elif abs_ratio >= 0.70:
                score += 10
                feedback_parts.append(f'[+10] Absolute Span partially correct ({correct_abs}/{valid_count}).')
            else:
                feedback_parts.append(f'[0] Absolute Span failed ({correct_abs}/{valid_count} correct).')

            partial_ratio = correct_partial / valid_count
            if partial_ratio >= 0.95:
                score += 25
                feedback_parts.append(f'[+25] Partial Span string alignment correct for {correct_partial}/{valid_count} valid participants.')
            elif partial_ratio >= 0.70:
                score += 10
                feedback_parts.append(f'[+10] Partial Span partially correct ({correct_partial}/{valid_count}).')
            else:
                feedback_parts.append(f'[0] Partial Span failed ({correct_partial}/{valid_count} correct).')

        # --- Criterion 5: Group Means (20 pts) ---
        ag_group_abs = report.get('group_mean_absolute_span')
        ag_group_partial = report.get('group_mean_partial_span')

        group_score = 0
        if ag_group_abs is not None and abs(float(ag_group_abs) - gt_group_abs) <= 0.5:
            group_score += 10
        if ag_group_partial is not None and abs(float(ag_group_partial) - gt_group_partial) <= 0.5:
            group_score += 10

        score += group_score
        if group_score == 20:
            feedback_parts.append('[+20] Group means correctly calculated and aggregated.')
        elif group_score == 10:
            feedback_parts.append('[+10] One of the group means was correctly calculated.')
        else:
            feedback_parts.append('[0] Group means incorrect or missing (did agent fail to exclude flagged participants from mean?).')

    passed = score >= PASS_THRESHOLD

    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback_parts)
    }