#!/usr/bin/env python3
"""
Verifier for ab_lag_accuracy_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Contaminated participant (p00) correctly excluded             (20 pts)
  3. All 24 valid participants present in report                   (15 pts)
  4. T2|T1 accuracy correct (±0.10) for ≥18 of 24 participants     (25 pts)
  5. AB magnitude correct (±0.10) for ≥18 of 24 participants       (15 pts)
  6. Group mean shows classic AB pattern (Lag1>Lag3 & Lag7>Lag3)   (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED = 'p00'
PASS_THRESHOLD = 60
ACC_TOLERANCE = 0.10
MAG_TOLERANCE = 0.10
MIN_CORRECT_PPTS = 18

def verify_ab_lag_accuracy_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}

    score = 0
    feedback_parts = []

    # --- Fetch Ground Truth ---
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_gt:
        tmp_gt_path = tmp_gt.name

    try:
        copy_from_env('/tmp/ab_ground_truth.json', tmp_gt_path)
        with open(tmp_gt_path, encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load ground truth: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load ground truth for verification."}
    finally:
        if os.path.exists(tmp_gt_path):
            os.unlink(tmp_gt_path)

    # --- Fetch Agent Output ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_rep:
        tmp_rep_path = tmp_rep.name

    try:
        copy_from_env('/home/ga/pebl/analysis/ab_report.json', tmp_rep_path)
        with open(tmp_rep_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/ab_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(tmp_rep_path):
            os.unlink(tmp_rep_path)

    # --- Build Participant Lookup ---
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
        if pid not in part_map:
            excluded_list = report.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
        return False

    # --- Criterion 2: p00 excluded (100% accuracy = impossible) ---
    if is_excluded(CONTAMINATED):
        score += 20
        feedback_parts.append('[+20] p00 correctly excluded.')
    else:
        feedback_parts.append('[0] p00 not excluded despite 100% accuracy at all lags.')

    # --- Criterion 3: All 24 valid participants present ---
    real_participants = set(gt_data['participants'].keys())
    present_real = real_participants.intersection(part_map.keys())
    if len(present_real) == 24:
        score += 15
        feedback_parts.append('[+15] All 24 real participants present.')
    elif len(present_real) >= 12:
        partial = 7
        score += partial
        feedback_parts.append(f'[+{partial}] {len(present_real)}/24 real participants present (partial).')
    else:
        feedback_parts.append(f'[0] Only {len(present_real)}/24 real participants present.')

    # --- Criterion 4 & 5: Accuracy & AB Magnitude ---
    correct_acc = 0
    correct_mag = 0

    for pid in present_real:
        gt_ppt = gt_data['participants'][pid]
        agent_ppt = part_map[pid]
        
        if is_excluded(pid):
            continue

        # Check T2|T1
        agent_t2 = agent_ppt.get('t2_given_t1', {})
        gt_t2 = gt_ppt['t2_given_t1']
        
        acc_match = True
        for lag in ['1', '2', '3', '4', '5', '7', '8']:
            val = agent_t2.get(lag)
            if val is None:
                acc_match = False
                break
            try:
                if abs(float(val) - gt_t2[lag]) > ACC_TOLERANCE:
                    acc_match = False
                    break
            except (TypeError, ValueError):
                acc_match = False
                break
                
        if acc_match:
            correct_acc += 1

        # Check Magnitude
        agent_mag = agent_ppt.get('ab_magnitude')
        if agent_mag is not None:
            try:
                if abs(float(agent_mag) - gt_ppt['ab_magnitude']) <= MAG_TOLERANCE:
                    correct_mag += 1
            except (TypeError, ValueError):
                pass

    if correct_acc >= MIN_CORRECT_PPTS:
        score += 25
        feedback_parts.append(f'[+25] T2|T1 correct for {correct_acc}/24 participants.')
    elif correct_acc >= 10:
        partial = 12
        score += partial
        feedback_parts.append(f'[+{partial}] T2|T1 correct for {correct_acc}/24 participants (partial).')
    else:
        feedback_parts.append(f'[0] T2|T1 correct for only {correct_acc}/24 participants.')

    if correct_mag >= MIN_CORRECT_PPTS:
        score += 15
        feedback_parts.append(f'[+15] AB magnitude correct for {correct_mag}/24 participants.')
    elif correct_mag >= 10:
        partial = 7
        score += partial
        feedback_parts.append(f'[+{partial}] AB magnitude correct for {correct_mag}/24 participants (partial).')
    else:
        feedback_parts.append(f'[0] AB magnitude correct for only {correct_mag}/24 participants.')

    # --- Criterion 6: Group Mean AB Pattern ---
    group_means = report.get('group_means', {})
    t2_means = group_means.get('t2_given_t1', {})
    try:
        l1 = float(t2_means.get('1', t2_means.get(1, -1)))
        l3 = float(t2_means.get('3', t2_means.get(3, -1)))
        l7 = float(t2_means.get('7', t2_means.get(7, -1)))

        if l1 != -1 and l3 != -1 and l7 != -1:
            if l1 > l3 and l7 > l3:
                score += 15
                feedback_parts.append('[+15] Group mean exhibits classic AB pattern (Lag 1 & 7 > Lag 3).')
            else:
                feedback_parts.append(f'[0] Group mean pattern incorrect. L1:{l1:.2f}, L3:{l3:.2f}, L7:{l7:.2f}. Expected L1>L3 and L7>L3.')
        else:
            feedback_parts.append('[0] Group means missing required lags 1, 3, or 7.')
    except (TypeError, ValueError):
        feedback_parts.append('[0] Group means not valid numbers.')

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }