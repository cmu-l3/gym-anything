#!/usr/bin/env python3
"""
Verifier for prob_reversal_wsls_analysis task.

Calculates ground truth dynamically from the environment's CSV to ensure absolute
accuracy, then verifies the agent's JSON report against it.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant PRL-999 is excluded                     (20 pts)
  3. All 18 real participants present in report                    (10 pts)
  4. Win-Stay rates within ±0.08 for ≥14 valid ppts                (15 pts)
  5. Lose-Shift rates within ±0.08 for ≥14 valid ppts              (15 pts)
  6. Perseverative error counts within ±3 for ≥14 valid ppts       (15 pts)
  7. Group mean Win-Stay within ±0.05 of ground truth              (7.5 pts)
  8. Group mean Lose-Shift within ±0.05 of ground truth            (7.5 pts)

Pass threshold: 60 pts
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED_PARTICIPANT = 'PRL-999'
PASS_THRESHOLD = 60
WSLS_TOLERANCE = 0.08
PERS_TOLERANCE = 3
GROUP_TOLERANCE = 0.05
MIN_CORRECT_PPTS = 14
TOTAL_VALID_PPTS = 18

def compute_ground_truth(csv_path):
    """Computes exact ground truth metrics dynamically from the raw CSV data."""
    participants = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in participants:
                participants[pid] = []
            participants[pid].append(row)

    results = {}
    for pid, trials in participants.items():
        if pid == CONTAMINATED_PARTICIPANT:
            continue
            
        win_stay_count = 0
        win_stay_possible = 0
        lose_shift_count = 0
        lose_shift_possible = 0
        
        # Sort trials by trial number just in case
        trials = sorted(trials, key=lambda x: int(x['trial']))
        reversal_trial = int(trials[0]['reversal_trial'])

        for i in range(len(trials)):
            t = trials[i]
            # WSLS (Trials 2-120)
            if i > 0:
                prev = trials[i-1]
                if prev['feedback'] == 'win':
                    win_stay_possible += 1
                    if t['choice'] == prev['choice']: win_stay_count += 1
                elif prev['feedback'] == 'lose':
                    lose_shift_possible += 1
                    if t['choice'] != prev['choice']: lose_shift_count += 1

        # Perseverative errors
        pers_errors = 0
        for i in range(len(trials)):
            t_num = int(trials[i]['trial'])
            if t_num >= reversal_trial:
                if trials[i]['choice'] == 'A' and trials[i]['feedback'] == 'lose':
                    pers_errors += 1
                else:
                    break # Stop at first B or first win on A

        results[pid] = {
            'win_stay_rate': win_stay_count / win_stay_possible if win_stay_possible else 0.0,
            'lose_shift_rate': lose_shift_count / lose_shift_possible if lose_shift_possible else 0.0,
            'perseverative_errors': pers_errors
        }
        
    return results

def verify_prob_reversal_wsls_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # Copy CSV and JSON from environment
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv, \
         tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json:
        tmp_csv_path = tmp_csv.name
        tmp_json_path = tmp_json.name

    try:
        copy_from_env('/home/ga/pebl/data/reversal_learning_data.csv', tmp_csv_path)
        if not os.path.exists(tmp_csv_path) or os.path.getsize(tmp_csv_path) == 0:
            return {"passed": False, "score": 0, "feedback": "Verifier Error: Could not copy raw data CSV."}
        
        gt_results = compute_ground_truth(tmp_csv_path)
        
        copy_from_env('/home/ga/pebl/analysis/reversal_report.json', tmp_json_path)
        if not os.path.exists(tmp_json_path) or os.path.getsize(tmp_json_path) == 0:
            feedback_parts.append("[0] Output file not found or empty.")
            return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
            
        with open(tmp_json_path, encoding='utf-8') as f:
            report = json.load(f)
            
        score += 10
        feedback_parts.append("[+10] Output file found and is valid JSON.")
    except json.JSONDecodeError as e:
        feedback_parts.append(f"[0] Output file is not valid JSON: {e}")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    except Exception as e:
        feedback_parts.append(f"[0] Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    finally:
        for p in [tmp_csv_path, tmp_json_path]:
            if os.path.exists(p):
                os.unlink(p)

    # Participant lookup
    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        if pid not in part_map:
            ex_list = report.get('excluded', [])
            if isinstance(ex_list, list) and pid in ex_list:
                return True
        return False

    # Criterion 2: Contaminated participant excluded
    if is_excluded(CONTAMINATED_PARTICIPANT):
        score += 20
        feedback_parts.append(f"[+20] Participant {CONTAMINATED_PARTICIPANT} correctly excluded.")
    else:
        feedback_parts.append(f"[0] Participant {CONTAMINATED_PARTICIPANT} not excluded despite mechanical response pattern.")

    # Criterion 3: Real participants present
    present_real = set(gt_results.keys()).intersection(part_map.keys())
    if len(present_real) == TOTAL_VALID_PPTS:
        score += 10
        feedback_parts.append(f"[+10] All {TOTAL_VALID_PPTS} real participants present.")
    elif len(present_real) > 0:
        partial = int((len(present_real) / TOTAL_VALID_PPTS) * 10)
        score += partial
        feedback_parts.append(f"[+{partial}] {len(present_real)}/{TOTAL_VALID_PPTS} real participants present.")
    else:
        feedback_parts.append(f"[0] No real participants found in report.")

    # Criteria 4, 5, 6: WSLS and Perseveration accuracy
    correct_ws = 0
    correct_ls = 0
    correct_pers = 0
    
    for pid, gt in gt_results.items():
        entry = part_map.get(pid)
        if not entry or is_excluded(pid): continue
        
        ws = entry.get('win_stay_rate')
        ls = entry.get('lose_shift_rate')
        pe = entry.get('perseverative_errors')
        
        if ws is not None:
            try:
                if abs(float(ws) - gt['win_stay_rate']) <= WSLS_TOLERANCE: correct_ws += 1
            except (ValueError, TypeError): pass
            
        if ls is not None:
            try:
                if abs(float(ls) - gt['lose_shift_rate']) <= WSLS_TOLERANCE: correct_ls += 1
            except (ValueError, TypeError): pass
            
        if pe is not None:
            try:
                if abs(float(pe) - gt['perseverative_errors']) <= PERS_TOLERANCE: correct_pers += 1
            except (ValueError, TypeError): pass

    # Win-Stay
    if correct_ws >= MIN_CORRECT_PPTS:
        score += 15
        feedback_parts.append(f"[+15] Win-Stay correct for {correct_ws}/{TOTAL_VALID_PPTS} valid participants.")
    elif correct_ws >= (MIN_CORRECT_PPTS - 5):
        score += 7.5
        feedback_parts.append(f"[+7.5] Win-Stay correct for {correct_ws}/{TOTAL_VALID_PPTS} valid participants.")
    else:
        feedback_parts.append(f"[0] Win-Stay correct for only {correct_ws}/{TOTAL_VALID_PPTS} valid participants.")

    # Lose-Shift
    if correct_ls >= MIN_CORRECT_PPTS:
        score += 15
        feedback_parts.append(f"[+15] Lose-Shift correct for {correct_ls}/{TOTAL_VALID_PPTS} valid participants.")
    elif correct_ls >= (MIN_CORRECT_PPTS - 5):
        score += 7.5
        feedback_parts.append(f"[+7.5] Lose-Shift correct for {correct_ls}/{TOTAL_VALID_PPTS} valid participants.")
    else:
        feedback_parts.append(f"[0] Lose-Shift correct for only {correct_ls}/{TOTAL_VALID_PPTS} valid participants.")

    # Perseverative Errors
    if correct_pers >= MIN_CORRECT_PPTS:
        score += 15
        feedback_parts.append(f"[+15] Perseverative errors correct for {correct_pers}/{TOTAL_VALID_PPTS} valid participants.")
    elif correct_pers >= (MIN_CORRECT_PPTS - 5):
        score += 7.5
        feedback_parts.append(f"[+7.5] Perseverative errors correct for {correct_pers}/{TOTAL_VALID_PPTS} valid participants.")
    else:
        feedback_parts.append(f"[0] Perseverative errors correct for only {correct_pers}/{TOTAL_VALID_PPTS} valid participants.")

    # Criteria 7, 8: Group Means
    group_means_agent = report.get('group_means', {})
    if isinstance(group_means_agent, dict):
        gt_group_ws = sum(r['win_stay_rate'] for r in gt_results.values()) / len(gt_results)
        gt_group_ls = sum(r['lose_shift_rate'] for r in gt_results.values()) / len(gt_results)
        
        agent_group_ws = group_means_agent.get('win_stay_rate')
        agent_group_ls = group_means_agent.get('lose_shift_rate')
        
        if agent_group_ws is not None:
            try:
                if abs(float(agent_group_ws) - gt_group_ws) <= GROUP_TOLERANCE:
                    score += 7.5
                    feedback_parts.append("[+7.5] Group mean Win-Stay is correct.")
                else:
                    feedback_parts.append(f"[0] Group mean Win-Stay incorrect (expected ~{gt_group_ws:.3f}, got {agent_group_ws}).")
            except (ValueError, TypeError): pass
            
        if agent_group_ls is not None:
            try:
                if abs(float(agent_group_ls) - gt_group_ls) <= GROUP_TOLERANCE:
                    score += 7.5
                    feedback_parts.append("[+7.5] Group mean Lose-Shift is correct.")
                else:
                    feedback_parts.append(f"[0] Group mean Lose-Shift incorrect (expected ~{gt_group_ls:.3f}, got {agent_group_ls}).")
            except (ValueError, TypeError): pass

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }