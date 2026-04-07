#!/usr/bin/env python3
"""
Verifier for flanker_gratton_effect_analysis task.

This verifier robustly calculates the expected ground truth dynamically 
by pulling the EXACT CSV file the agent was working on from the container 
environment. This ensures perfectly fair evaluation.

Scoring (100 pts total):
  1. Output file exists, is valid JSON, and has correct structure (10 pts)
  2. Contaminated participant s99 is successfully excluded          (20 pts)
  3. All 27 real participants are present in the report             (20 pts)
  4. Transition RTs correctly calculated for ≥ 80% of participants  (20 pts)
  5. Gratton Effect correctly calculated for ≥ 80% of participants  (20 pts)
  6. Group Mean Gratton Effect within ±2.5ms of ground truth        (10 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import numpy as np
import pandas as pd

CONTAMINATED_PARTICIPANT = 's99'
PASS_THRESHOLD = 60
RT_TOLERANCE_MS = 2.0
GRATTON_TOLERANCE_MS = 2.5
GROUP_MEAN_TOLERANCE_MS = 2.0

def compute_ground_truth(csv_path):
    """Dynamically compute the exact ground truth from the given CSV file."""
    df = pd.read_csv(csv_path)
    # Convert RT from seconds to ms
    df['rt_ms'] = df['rt'] * 1000.0
    
    # Strictly filter out 'neutral'
    df = df[df['flankers'].isin(['congruent', 'incongruent'])].copy()
    
    # Sort chronologically
    df['trial'] = pd.to_numeric(df['trial'], errors='coerce')
    df['block'] = pd.to_numeric(df['block'], errors='coerce')
    df = df.sort_values(['participant', 'block', 'trial'])
    
    gt = {}
    valid_grattons = []

    for pid, group in df.groupby('participant'):
        pid_str = str(pid)
        if pid_str == CONTAMINATED_PARTICIPANT:
            continue
            
        # Shift to get the previous trial's condition within the SAME block
        group['prev_flankers'] = group.groupby('block')['flankers'].shift(1)
        
        # Drop rows where there is no previous trial
        group = group.dropna(subset=['prev_flankers'])
        
        cC = group[(group['prev_flankers'] == 'congruent') & (group['flankers'] == 'congruent')]['rt_ms'].mean()
        cI = group[(group['prev_flankers'] == 'congruent') & (group['flankers'] == 'incongruent')]['rt_ms'].mean()
        iC = group[(group['prev_flankers'] == 'incongruent') & (group['flankers'] == 'congruent')]['rt_ms'].mean()
        iI = group[(group['prev_flankers'] == 'incongruent') & (group['flankers'] == 'incongruent')]['rt_ms'].mean()
        
        gratton = (cI - cC) - (iI - iC)
        
        if not np.isnan(gratton):
            valid_grattons.append(gratton)
            
        gt[pid_str] = {
            'cC': cC,
            'cI': cI,
            'iC': iC,
            'iI': iI,
            'gratton': gratton
        }
        
    return gt, np.nanmean(valid_grattons)

def verify_flanker_gratton_effect_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    score = 0
    feedback_parts = []

    # --- Step 1: Fetch and compute ground truth dynamically ---
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        csv_path = tmp_csv.name

    try:
        copy_from_env('/home/ga/pebl/data/flanker_data.csv', csv_path)
        ground_truth, group_mean_gt = compute_ground_truth(csv_path)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f"Failed to compute ground truth from CSV: {e}"}
    finally:
        if os.path.exists(csv_path):
            os.unlink(csv_path)

    # --- Step 2: Fetch and validate agent's JSON output ---
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json:
        json_path = tmp_json.name

    try:
        copy_from_env('/home/ga/pebl/analysis/gratton_report.json', json_path)
        with open(json_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/gratton_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file is not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(json_path):
            os.unlink(json_path)

    participants_list = report.get('participants', [])
    if not isinstance(participants_list, list):
        feedback_parts.append('[0] "participants" key missing or not a list.')
        return {'passed': False, 'score': score, 'feedback': ' '.join(feedback_parts)}

    # Build lookup dictionary
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    # Helper function to check close values ignoring NaNs
    def is_close(ag_val, gt_val, tol):
        if np.isnan(gt_val):
            return True  # If GT is NaN, any or missing from agent is acceptable
        if ag_val is None:
            return False
        try:
            return abs(float(ag_val) - gt_val) <= tol
        except (ValueError, TypeError):
            return False

    # --- Criterion 2: Contaminated participant excluded ---
    s99_entry = part_map.get(CONTAMINATED_PARTICIPANT)
    if s99_entry and s99_entry.get('excluded') in (True, 'true', 1, 'yes'):
        score += 20
        feedback_parts.append(f'[+20] Contaminated participant {CONTAMINATED_PARTICIPANT} correctly excluded.')
    elif CONTAMINATED_PARTICIPANT not in part_map:
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and CONTAMINATED_PARTICIPANT in excluded_list:
            score += 20
            feedback_parts.append(f'[+20] {CONTAMINATED_PARTICIPANT} excluded via top-level excluded list.')
        else:
            feedback_parts.append(f'[0] {CONTAMINATED_PARTICIPANT} completely missing, assuming excluded.')
            score += 20
    else:
        feedback_parts.append(f'[0] {CONTAMINATED_PARTICIPANT} present and not marked as excluded.')

    # --- Criterion 3: All real participants present ---
    real_pids = set(ground_truth.keys())
    present_pids = real_pids.intersection(part_map.keys())
    
    if len(present_pids) == len(real_pids):
        score += 20
        feedback_parts.append(f'[+20] All {len(real_pids)} real participants present.')
    elif len(present_pids) >= 20:
        partial = 10
        score += partial
        feedback_parts.append(f'[+{partial}] {len(present_pids)}/{len(real_pids)} participants present.')
    else:
        feedback_parts.append(f'[0] Only {len(present_pids)}/{len(real_pids)} participants present.')

    # --- Criteria 4 & 5: Transition RTs & Gratton Effects ---
    correct_transitions = 0
    correct_gratton = 0

    for pid in present_pids:
        entry = part_map[pid]
        gt_vals = ground_truth[pid]

        if entry.get('excluded') in (True, 'true', 1, 'yes'):
            continue

        # Extract values
        cC = entry.get('cC_mean_ms')
        cI = entry.get('cI_mean_ms')
        iC = entry.get('iC_mean_ms')
        iI = entry.get('iI_mean_ms')
        gratton = entry.get('gratton_effect_ms')

        if (is_close(cC, gt_vals['cC'], RT_TOLERANCE_MS) and
            is_close(cI, gt_vals['cI'], RT_TOLERANCE_MS) and
            is_close(iC, gt_vals['iC'], RT_TOLERANCE_MS) and
            is_close(iI, gt_vals['iI'], RT_TOLERANCE_MS)):
            correct_transitions += 1

        if is_close(gratton, gt_vals['gratton'], GRATTON_TOLERANCE_MS):
            correct_gratton += 1

    req_count = max(1, int(len(real_pids) * 0.8))
    
    if correct_transitions >= req_count:
        score += 20
        feedback_parts.append(f'[+20] Transition RTs accurate for {correct_transitions} valid participants.')
    elif correct_transitions >= req_count // 2:
        score += 10
        feedback_parts.append(f'[+10] Transition RTs accurate for {correct_transitions} participants (partial).')
    else:
        feedback_parts.append(f'[0] Transition RTs accurate for only {correct_transitions} participants.')

    if correct_gratton >= req_count:
        score += 20
        feedback_parts.append(f'[+20] Gratton Effect accurate for {correct_gratton} valid participants.')
    elif correct_gratton >= req_count // 2:
        score += 10
        feedback_parts.append(f'[+10] Gratton Effect accurate for {correct_gratton} participants (partial).')
    else:
        feedback_parts.append(f'[0] Gratton Effect accurate for only {correct_gratton} participants.')

    # --- Criterion 6: Group Mean ---
    ag_group_mean = report.get('group_mean_gratton_ms')
    if is_close(ag_group_mean, group_mean_gt, GROUP_MEAN_TOLERANCE_MS):
        score += 10
        feedback_parts.append(f'[+10] Group mean {ag_group_mean} is within tolerance (GT: {group_mean_gt:.2f}).')
    else:
        feedback_parts.append(f'[0] Group mean {ag_group_mean} incorrect (GT: {group_mean_gt:.2f}).')

    passed = score >= PASS_THRESHOLD
    
    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join(feedback_parts)
    }