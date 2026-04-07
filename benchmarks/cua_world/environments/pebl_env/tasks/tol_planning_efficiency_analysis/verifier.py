#!/usr/bin/env python3
"""
Verifier for tol_planning_efficiency_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. sub-99 correctly excluded with reason                         (20 pts)
  3. All 20 real participants present with by_difficulty data      (15 pts)
  4. Proportion optimal within tolerance                           (10 pts)
  5. Mean excess moves within tolerance                            (10 pts)
  6. Mean planning time within tolerance                           (10 pts)
  7. Planning slope within tolerance                               (15 pts)
  8. Group mean planning slope within tolerance                    (10 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile

CONTAMINATED = 'sub-99'
PASS_THRESHOLD = 60

def verify_tol_planning_efficiency_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    # 1. Output file exists and is valid JSON
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/tol_report.json', tmp_path)
        with open(tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/tol_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    # 2. Load ground truth
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_gt:
        tmp_gt_path = tmp_gt.name
    try:
        copy_from_env('/tmp/tol_ground_truth.json', tmp_gt_path)
        with open(tmp_gt_path, encoding='utf-8') as f:
            gt = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Failed to load ground truth: {e}'}
    finally:
        try:
            os.unlink(tmp_gt_path)
        except Exception:
            pass

    gt_participants = gt['participants']
    gt_slopes = gt['slopes']
    gt_group_mean_slope = gt['group_mean_slope']

    # Build participant lookup
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

    # 3. sub-99 excluded
    if is_excluded(CONTAMINATED):
        score += 20
        feedback_parts.append(f'[+20] {CONTAMINATED} correctly excluded.')
    else:
        feedback_parts.append(f'[0] {CONTAMINATED} not excluded.')

    # 4. Check real participants
    real_pids = set(gt_participants.keys())
    present_real = real_pids.intersection(part_map.keys())
    if len(present_real) == 20:
        score += 15
        feedback_parts.append('[+15] All 20 real participants present.')
    else:
        feedback_parts.append(f'[0] Only {len(present_real)}/20 real participants present.')

    # Evaluate metrics per participant
    correct_prop = 0
    correct_exc = 0
    correct_time = 0
    correct_slope = 0
    
    for pid in present_real:
        if is_excluded(pid):
            continue
        
        entry = part_map[pid]
        by_diff = entry.get('by_difficulty') or entry.get('set_sizes') or entry.get('difficulties', {})
        
        if not by_diff:
            continue
            
        diffs_ok_prop = 0
        diffs_ok_exc = 0
        diffs_ok_time = 0
        
        for d in ['2', '3', '4', '5', '6', '7']:
            gt_diff = gt_participants[pid].get(d)
            if not gt_diff:
                continue
                
            pred_diff = by_diff.get(d) or by_diff.get(int(d))
            if not pred_diff:
                continue
                
            try:
                # proportion optimal
                prop = pred_diff.get('proportion_optimal')
                if prop is not None and abs(float(prop) - gt_diff['proportion_optimal']) <= 0.05:
                    diffs_ok_prop += 1
                
                # mean excess moves
                exc = pred_diff.get('mean_excess_moves')
                if exc is not None and abs(float(exc) - gt_diff['mean_excess_moves']) <= 0.1:
                    diffs_ok_exc += 1
                    
                # mean planning time
                time = pred_diff.get('mean_planning_time_ms')
                if time is not None and abs(float(time) - gt_diff['mean_planning_time_ms']) <= 10.0:
                    diffs_ok_time += 1
            except (ValueError, TypeError):
                pass
                
        if diffs_ok_prop == 6: correct_prop += 1
        if diffs_ok_exc == 6: correct_exc += 1
        if diffs_ok_time == 6: correct_time += 1
        
        # planning slope
        slope = entry.get('planning_slope_ms_per_move')
        if slope is not None:
            try:
                if abs(float(slope) - gt_slopes[pid]) <= 5.0:
                    correct_slope += 1
            except (ValueError, TypeError):
                pass

    if correct_prop >= 15:
        score += 10
        feedback_parts.append(f'[+10] Proportion optimal correct for {correct_prop}/20 participants.')
    else:
        feedback_parts.append(f'[0] Proportion optimal correct for only {correct_prop}/20 participants.')

    if correct_exc >= 15:
        score += 10
        feedback_parts.append(f'[+10] Mean excess moves correct for {correct_exc}/20 participants.')
    else:
        feedback_parts.append(f'[0] Mean excess moves correct for only {correct_exc}/20 participants.')
        
    if correct_time >= 15:
        score += 10
        feedback_parts.append(f'[+10] Mean planning time correct for {correct_time}/20 participants.')
    else:
        feedback_parts.append(f'[0] Mean planning time correct for only {correct_time}/20 participants.')
        
    if correct_slope >= 12:
        score += 15
        feedback_parts.append(f'[+15] Planning slope correct for {correct_slope}/20 participants.')
    else:
        feedback_parts.append(f'[0] Planning slope correct for only {correct_slope}/20 participants.')

    # Group mean slope
    group_slope = report.get('group_mean_planning_slope_ms_per_move')
    if group_slope is not None:
        try:
            if abs(float(group_slope) - gt_group_mean_slope) <= 10.0:
                score += 10
                feedback_parts.append(f'[+10] Group mean planning slope within tolerance.')
            else:
                feedback_parts.append(f'[0] Group mean planning slope mismatch. Expected ~{gt_group_mean_slope:.1f}, got {group_slope}.')
        except (ValueError, TypeError):
            feedback_parts.append('[0] Group mean planning slope is not a valid number.')
    else:
        feedback_parts.append('[0] Group mean planning slope not found.')

    passed = score >= PASS_THRESHOLD
    
    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join(feedback_parts)
    }