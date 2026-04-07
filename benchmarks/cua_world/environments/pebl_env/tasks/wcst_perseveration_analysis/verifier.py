#!/usr/bin/env python3
"""
Verifier for wcst_perseveration_analysis task.

Computes precise dynamic ground truth directly from the agent's input CSV using
the strict Heaton (1993) rules described in the prompt to prevent any mismatch.

Scoring (100 pts total):
  1. Output file exists and is valid JSON (10 pts)
  2. sub-99999 correctly excluded (20 pts)
  3. All 12 valid participants present (10 pts)
  4. Categories completed exact match for >=9 of 12 (15 pts)
  5. Perseverative errors within +/-3 for >=9 of 12 (20 pts)
  6. Total errors within +/-5 for >=9 of 12 (10 pts)
  7. Group mean perseverative errors within +/-3 (15 pts)

Anti-gaming: Output must be created DURING the task.
"""

import json
import os
import tempfile
import csv

CONTAMINATED = 'sub-99999'

def compute_ground_truth(csv_path):
    participants = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in participants:
                participants[pid] = []
            participants[pid].append(row)

    results = {}
    PILES = {
        '1': {'color': 'red', 'shape': 'triangle', 'number': '1'},
        '2': {'color': 'green', 'shape': 'star', 'number': '2'},
        '3': {'color': 'yellow', 'shape': 'cross', 'number': '3'},
        '4': {'color': 'blue', 'shape': 'circle', 'number': '4'}
    }

    for pid, trials in participants.items():
        if pid == CONTAMINATED:
            continue
            
        categories_completed = 0
        consecutive_correct = 0
        trials_to_first = 128
        pe = 0
        npe = 0
        fms = 0
        
        correct_run_lengths = []
        current_run = 0

        rule_sequence_observed = []
        for t in trials:
            r = t['current_rule']
            if not rule_sequence_observed or rule_sequence_observed[-1] != r:
                rule_sequence_observed.append(r)

        cat_index = 0

        for i, t in enumerate(trials):
            pile = t['response_pile']
            stim = {'color': t['stimulus_color'], 'shape': t['stimulus_shape'], 'number': t['stimulus_number']}
            curr_rule = t['current_rule']
            
            is_correct = (PILES[pile][curr_rule] == stim[curr_rule])

            prev_rule = None
            if categories_completed > 0:
                if cat_index > 0 and cat_index <= len(rule_sequence_observed):
                    prev_rule = rule_sequence_observed[cat_index - 1]

            is_persev_response = False
            if prev_rule:
                is_persev_response = (PILES[pile][prev_rule] == stim[prev_rule])

            if is_correct:
                consecutive_correct += 1
                current_run += 1
                
                if consecutive_correct == 10:
                    categories_completed += 1
                    cat_index += 1
                    if categories_completed == 1:
                        trials_to_first = i + 1
                    consecutive_correct = 0
            else:
                if is_persev_response:
                    pe += 1
                else:
                    npe += 1
                    
                if 5 <= consecutive_correct < 10:
                    fms += 1
                
                if current_run > 0:
                    correct_run_lengths.append(current_run)
                current_run = 0
                consecutive_correct = 0

        if current_run > 0:
            correct_run_lengths.append(current_run)

        clr_trials = sum(r for r in correct_run_lengths if r >= 3)
        clr_pct = (clr_trials / len(trials)) * 100 if len(trials) > 0 else 0.0

        results[pid] = {
            'categories_completed': categories_completed,
            'perseverative_errors': pe,
            'total_errors': pe + npe,
            'conceptual_level_pct': round(clr_pct, 1)
        }

    return results


def verify_wcst_perseveration_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing."}

    score = 0
    feedback_parts = []

    # Verify anti-gaming
    export_meta = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                export_meta = json.load(f)
        except Exception:
            pass
        finally:
            os.unlink(tmp.name)

    if export_meta and str(export_meta.get('file_created_during_task')).lower() == 'false':
        return {"passed": False, "score": 0, "feedback": "Fail: Output file was not created or modified during the task session."}

    # Fetch ground truth dynamically
    ground_truth = {}
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        try:
            copy_from_env('/home/ga/pebl/data/wcst_data.csv', tmp_csv.name)
            ground_truth = compute_ground_truth(tmp_csv.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"System error reading source CSV: {e}"}
        finally:
            os.unlink(tmp_csv.name)

    gt_mean_pe = sum(p['perseverative_errors'] for p in ground_truth.values()) / len(ground_truth)

    # 1. Output file exists and is valid JSON
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/wcst_report.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Report exists and is valid JSON.')
    except FileNotFoundError:
        return {'passed': False, 'score': 0, 'feedback': 'Output file not found.'}
    except (json.JSONDecodeError, ValueError):
        return {'passed': False, 'score': 0, 'feedback': 'Output file is not valid JSON.'}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    part_map = {}
    for entry in report.get('participants', []):
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    # 2. sub-99999 excluded
    s99 = part_map.get(CONTAMINATED)
    if s99 and s99.get('excluded') in (True, 'true', 1, 'yes'):
        score += 20
        feedback_parts.append('[+20] sub-99999 excluded.')
    else:
        feedback_parts.append('[0] sub-99999 not explicitly excluded.')

    # 3. All 12 valid participants present
    valid_pids = set(ground_truth.keys())
    present = valid_pids.intersection(part_map.keys())
    if len(present) == 12:
        score += 10
        feedback_parts.append('[+10] All 12 valid participants present.')
    else:
        feedback_parts.append(f'[0] Only {len(present)}/12 valid participants present.')

    # Evaluate metrics
    correct_cat = 0
    correct_pe = 0
    correct_te = 0

    for pid, gt in ground_truth.items():
        entry = part_map.get(pid, {})
        if entry.get('excluded') in (True, 'true', 1, 'yes'): continue

        try:
            if int(entry.get('categories_completed', -1)) == gt['categories_completed']:
                correct_cat += 1
            if abs(float(entry.get('perseverative_errors', -999)) - gt['perseverative_errors']) <= 3.0:
                correct_pe += 1
            if abs(float(entry.get('total_errors', -999)) - gt['total_errors']) <= 5.0:
                correct_te += 1
        except (TypeError, ValueError):
            pass

    # 4. Categories completed
    if correct_cat >= 9:
        score += 15
        feedback_parts.append(f'[+15] Categories match for {correct_cat}/12 participants.')
    else:
        feedback_parts.append(f'[0] Categories match for only {correct_cat}/12.')

    # 5. Perseverative errors
    if correct_pe >= 9:
        score += 20
        feedback_parts.append(f'[+20] Perseverative errors correct for {correct_pe}/12.')
    else:
        feedback_parts.append(f'[0] Perseverative errors correct for only {correct_pe}/12.')

    # 6. Total errors
    if correct_te >= 9:
        score += 10
        feedback_parts.append(f'[+10] Total errors correct for {correct_te}/12.')
    else:
        feedback_parts.append(f'[0] Total errors correct for only {correct_te}/12.')

    # 7. Group mean perseverative errors
    grp_means = report.get('group_means', {})
    rep_mean_pe = grp_means.get('perseverative_errors', -999)
    try:
        if abs(float(rep_mean_pe) - gt_mean_pe) <= 3.0:
            score += 15
            feedback_parts.append('[+15] Group mean perseverative errors accurate.')
        else:
            feedback_parts.append(f'[0] Group mean PE inaccurate (got {rep_mean_pe}, expected ~{gt_mean_pe:.1f}).')
    except (TypeError, ValueError):
        feedback_parts.append('[0] Group mean PE missing or invalid.')

    passed = score >= 60
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}