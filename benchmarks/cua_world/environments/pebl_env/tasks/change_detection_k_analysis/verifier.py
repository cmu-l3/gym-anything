#!/usr/bin/env python3
"""
Verifier for change_detection_k_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant p25 is excluded                         (20 pts)
  3. All 20 valid participants present                             (10 pts)
  4. K values correct across set sizes 2, 4, 6, 8 (10 pts each)    (40 pts)
  5. Estimated capacity correct (max K)                            (10 pts)
  6. Group mean capacity correct                                   (10 pts)

Pass threshold: 60 pts

Ground truth is computed dynamically by the verifier by reading the generated CSV
from the container to ensure robustness against generation randomness.
"""

import json
import os
import csv
import tempfile
from collections import defaultdict

PASS_THRESHOLD = 60
CONTAMINATED_PARTICIPANT = 'p25'
K_TOLERANCE = 0.3
CAPACITY_TOLERANCE = 0.5
GROUP_CAPACITY_TOLERANCE = 0.3


def safe_float(v):
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def verify_change_detection_k_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # --- Step 1: Compute Ground Truth from Container CSV ---
    gt_data = defaultdict(lambda: defaultdict(lambda: {'cp': 0, 'ca': 0, 'hits': 0, 'fas': 0}))
    
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        csv_path = tmp_csv.name
        
    try:
        copy_from_env('/home/ga/pebl/data/change_detection_data.csv', csv_path)
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                pid = row['participant_id']
                ss = int(row['set_size'])
                cp = int(row['change_present'])
                resp = int(row['response'])
                
                if cp == 1:
                    gt_data[pid][ss]['cp'] += 1
                    if resp == 1:
                        gt_data[pid][ss]['hits'] += 1
                else:
                    gt_data[pid][ss]['ca'] += 1
                    if resp == 1:
                        gt_data[pid][ss]['fas'] += 1
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Failed to retrieve or parse ground truth CSV: {e}'}
    finally:
        if os.path.exists(csv_path):
            os.unlink(csv_path)

    # Compute K values and Capacities
    gt_k = {}
    gt_cap = {}
    for pid, ss_data in gt_data.items():
        if pid == CONTAMINATED_PARTICIPANT:
            continue
        gt_k[pid] = {}
        caps = []
        for ss in [2, 4, 6, 8]:
            counts = ss_data[ss]
            H = counts['hits'] / max(1, counts['cp'])
            F = counts['fas'] / max(1, counts['ca'])
            K = max(0.0, float(ss) * (H - F))
            gt_k[pid][str(ss)] = K
            caps.append(K)
        gt_cap[pid] = max(caps)
    
    gt_group_cap = sum(gt_cap.values()) / len(gt_cap)

    # --- Step 2: Evaluate Agent's JSON Report ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json:
        json_path = tmp_json.name

    try:
        copy_from_env('/home/ga/pebl/analysis/k_capacity_report.json', json_path)
        with open(json_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output JSON found and parsed.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output /home/ga/pebl/analysis/k_capacity_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file invalid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(json_path):
            os.unlink(json_path)

    agent_map = {}
    for entry in report.get('participants', []):
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            agent_map[str(pid)] = entry

    def is_excluded(pid):
        entry = agent_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and pid in excluded_list:
            return True
        return False

    # Criterion: p25 excluded
    if is_excluded(CONTAMINATED_PARTICIPANT):
        score += 20
        feedback_parts.append('[+20] p25 correctly excluded.')
    else:
        feedback_parts.append(f'[0] {CONTAMINATED_PARTICIPANT} not excluded despite impossible accuracy pattern.')

    # Criterion: All 20 real participants present
    valid_present = sum(1 for pid in gt_k if pid in agent_map and not is_excluded(pid))
    if valid_present == 20:
        score += 10
        feedback_parts.append('[+10] All 20 valid participants present.')
    else:
        feedback_parts.append(f'[0] Only {valid_present}/20 valid participants present.')

    # Criteria: K values at set sizes 2, 4, 6, 8
    set_sizes = ['2', '4', '6', '8']
    for ss in set_sizes:
        correct_k = 0
        for pid, true_k_dict in gt_k.items():
            agent_pt = agent_map.get(pid)
            if agent_pt and not is_excluded(pid):
                agent_k = safe_float(agent_pt.get('k_by_setsize', {}).get(ss))
                if agent_k is not None and abs(agent_k - true_k_dict[ss]) <= K_TOLERANCE:
                    correct_k += 1
        
        if correct_k >= 16:
            score += 10
            feedback_parts.append(f'[+10] K values at set_size={ss} correct for {correct_k}/20 participants.')
        elif correct_k >= 10:
            score += 5
            feedback_parts.append(f'[+5] K values at set_size={ss} correct for {correct_k}/20 participants (partial).')
        else:
            feedback_parts.append(f'[0] K values at set_size={ss} correct for only {correct_k}/20 participants.')

    # Criterion: Estimated capacity
    correct_cap = 0
    for pid, true_cap in gt_cap.items():
        agent_pt = agent_map.get(pid)
        if agent_pt and not is_excluded(pid):
            agent_cap = safe_float(agent_pt.get('estimated_capacity'))
            if agent_cap is not None and abs(agent_cap - true_cap) <= CAPACITY_TOLERANCE:
                correct_cap += 1
                
    if correct_cap >= 16:
        score += 10
        feedback_parts.append(f'[+10] Estimated capacities correct for {correct_cap}/20 participants.')
    elif correct_cap >= 10:
        score += 5
        feedback_parts.append(f'[+5] Estimated capacities correct for {correct_cap}/20 participants (partial).')
    else:
        feedback_parts.append(f'[0] Estimated capacities correct for only {correct_cap}/20 participants.')

    # Criterion: Group mean capacity
    agent_group_cap = safe_float(report.get('group_mean_capacity'))
    if agent_group_cap is not None and abs(agent_group_cap - gt_group_cap) <= GROUP_CAPACITY_TOLERANCE:
        score += 10
        feedback_parts.append(f'[+10] Group mean capacity correct ({agent_group_cap:.2f} vs {gt_group_cap:.2f}).')
    else:
        feedback_parts.append(f'[0] Group mean capacity incorrect or missing (expected ~{gt_group_cap:.2f}).')

    passed = score >= PASS_THRESHOLD
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }