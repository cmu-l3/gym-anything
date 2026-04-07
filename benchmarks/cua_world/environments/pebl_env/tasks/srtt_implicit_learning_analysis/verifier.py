#!/usr/bin/env python3
"""
Verifier for srtt_implicit_learning_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant p99 is excluded with reason             (20 pts)
  3. All 15 valid participants present                             (10 pts)
  4. Block means within ±25ms for ≥12 valid participants           (20 pts)
  5. Sequence learning scores within ±20ms for ≥12 participants    (15 pts)
  6. General speedup scores within ±20ms for ≥12 participants      (10 pts)
  7. Group mean sequence learning within ±12ms of ground truth     (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import csv
import tempfile
from collections import defaultdict

CONTAMINATED_PARTICIPANT = 'p99'
PASS_THRESHOLD = 60

# Tolerances
BLOCK_MEAN_TOLERANCE = 25.0
LEARNING_TOLERANCE = 20.0
GROUP_MEAN_TOLERANCE = 12.0
MIN_CORRECT_PPTS = 12


def compute_ground_truth(csv_path):
    """Dynamically compute ground truth metrics directly from the generated CSV."""
    block_rts = defaultdict(lambda: defaultdict(list))
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Only use correct trials
            if str(row['correct']) == '1':
                pid = row['participant']
                block = int(row['block'])
                rt = float(row['rt_ms'])
                block_rts[pid][block].append(rt)
                
    gt_metrics = {}
    valid_pids = [f"p{i:02d}" for i in range(1, 16)]
    
    group_seq_learn_sum = 0
    
    for pid in valid_pids:
        b_means = {}
        for b in range(1, 9):
            rts = block_rts[pid].get(b, [])
            b_means[b] = sum(rts) / len(rts) if rts else 0.0
            
        seq_learn = b_means[6] - b_means[5]
        gen_speedup = b_means[1] - b_means[5]
        recovery = b_means[6] - b_means[7]
        
        gt_metrics[pid] = {
            'block_means_ms': [b_means[i] for i in range(1, 9)],
            'sequence_learning_ms': seq_learn,
            'general_speedup_ms': gen_speedup,
            'recovery_ms': recovery
        }
        group_seq_learn_sum += seq_learn
        
    group_mean_seq_learning = group_seq_learn_sum / len(valid_pids)
    
    return gt_metrics, group_mean_seq_learning


def verify_srtt_implicit_learning_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # Get data and report files
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json, \
         tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        tmp_json_path = tmp_json.name
        tmp_csv_path = tmp_csv.name

    try:
        # Retrieve the CSV first to compute Ground Truth
        copy_from_env('/home/ga/pebl/data/srtt_data.csv', tmp_csv_path)
        gt_metrics, gt_group_seq_learning = compute_ground_truth(tmp_csv_path)
        
        # Retrieve the JSON report
        copy_from_env('/home/ga/pebl/analysis/srtt_report.json', tmp_json_path)
        with open(tmp_json_path, encoding='utf-8') as f:
            report = json.load(f)
            
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Required files not found in the environment.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        for p in [tmp_json_path, tmp_csv_path]:
            try:
                os.unlink(p)
            except:
                pass

    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    # Helpers
    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        if pid not in part_map:
            excluded_list = report.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
        return False

    # Criterion 2: Corrupted participant excluded
    if is_excluded(CONTAMINATED_PARTICIPANT):
        score += 20
        feedback_parts.append('[+20] p99 correctly excluded.')
    else:
        feedback_parts.append('[0] p99 not excluded despite zero RT variance.')

    # Criterion 3: All 15 valid participants present
    valid_pids = set(gt_metrics.keys())
    present_valid = [p for p in valid_pids if p in part_map and not is_excluded(p)]
    if len(present_valid) == 15:
        score += 10
        feedback_parts.append('[+10] All 15 valid participants present.')
    else:
        feedback_parts.append(f'[0] Only {len(present_valid)}/15 valid participants present.')

    # Evaluation counters
    correct_block_means = 0
    correct_seq_learn = 0
    correct_gen_speedup = 0

    for pid in present_valid:
        entry = part_map[pid]
        gt = gt_metrics[pid]
        
        # Check block means
        b_means = entry.get('block_means_ms', [])
        if isinstance(b_means, list) and len(b_means) == 8:
            diffs = [abs(float(b_means[i]) - gt['block_means_ms'][i]) for i in range(8)]
            if max(diffs) <= BLOCK_MEAN_TOLERANCE:
                correct_block_means += 1

        # Check sequence learning
        seq_l = entry.get('sequence_learning_ms')
        if seq_l is not None:
            if abs(float(seq_l) - gt['sequence_learning_ms']) <= LEARNING_TOLERANCE:
                correct_seq_learn += 1

        # Check general speedup
        gen_s = entry.get('general_speedup_ms')
        if gen_s is not None:
            if abs(float(gen_s) - gt['general_speedup_ms']) <= LEARNING_TOLERANCE:
                correct_gen_speedup += 1

    # Criterion 4: Block means
    if correct_block_means >= MIN_CORRECT_PPTS:
        score += 20
        feedback_parts.append(f'[+20] Block means correct for {correct_block_means}/15 participants.')
    elif correct_block_means >= 5:
        score += 10
        feedback_parts.append(f'[+10] Block means correct for {correct_block_means}/15 participants (partial).')
    else:
        feedback_parts.append(f'[0] Block means correct for only {correct_block_means}/15 participants.')

    # Criterion 5: Sequence learning
    if correct_seq_learn >= MIN_CORRECT_PPTS:
        score += 15
        feedback_parts.append(f'[+15] Sequence learning correct for {correct_seq_learn}/15 participants.')
    elif correct_seq_learn >= 5:
        score += 7
        feedback_parts.append(f'[+7] Sequence learning correct for {correct_seq_learn}/15 participants (partial).')
    else:
        feedback_parts.append(f'[0] Sequence learning correct for only {correct_seq_learn}/15 participants.')

    # Criterion 6: General speedup
    if correct_gen_speedup >= MIN_CORRECT_PPTS:
        score += 10
        feedback_parts.append(f'[+10] General speedup correct for {correct_gen_speedup}/15 participants.')
    else:
        feedback_parts.append(f'[0] General speedup correct for only {correct_gen_speedup}/15 participants.')

    # Criterion 7: Group mean sequence learning
    group_means = report.get('group_means', {})
    rep_group_seq = group_means.get('sequence_learning_ms')
    if rep_group_seq is not None:
        try:
            if abs(float(rep_group_seq) - gt_group_seq_learning) <= GROUP_MEAN_TOLERANCE:
                score += 15
                feedback_parts.append('[+15] Group mean sequence learning is correct.')
            else:
                feedback_parts.append(f'[0] Group mean sequence learning {float(rep_group_seq):.1f} outside tolerance (expected ~{gt_group_seq_learning:.1f}).')
        except ValueError:
            feedback_parts.append('[0] Group mean sequence learning is not a valid number.')
    else:
        feedback_parts.append('[0] Group mean sequence learning not found.')

    passed = score >= PASS_THRESHOLD
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }