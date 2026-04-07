#!/usr/bin/env python3
"""
Verifier for vwm_color_reproduction_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. s99 correctly excluded (uniform random responding)            (15 pts)
  3. Circular Math / MAE correctly computed (tests circular dist)  (25 pts)
  4. Proxy metrics (Guess Rate & Precision SD) computed correctly  (30 pts)
  5. Group means correctly aggregated                              (20 pts)

Pass threshold: 60 pts, MUST have at least partial Circular Math points.
"""

import json
import os
import tempfile
import csv
import math

def compute_gt(csv_path):
    participants = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            ss = int(row['set_size'])
            target = float(row['target_color'])
            response = float(row['response_color'])
            
            signed_error = ((response - target + 180) % 360) - 180
            abs_error = abs(signed_error)
            
            if pid not in participants:
                participants[pid] = {1: [], 2: [], 4: [], 8: []}
            participants[pid][ss].append((signed_error, abs_error))
            
    results = {}
    for pid, sizes in participants.items():
        results[pid] = {}
        total_trials = 0
        total_guesses = 0
        for ss, errors in sizes.items():
            abs_errs = [e[1] for e in errors]
            signed_errs = [e[0] for e in errors]
            
            mae = sum(abs_errs) / len(abs_errs) if abs_errs else 0
            guesses = sum(1 for a in abs_errs if a > 60)
            guess_rate = guesses / len(abs_errs) if abs_errs else 0
            
            precision_errs = [e[0] for e in errors if e[1] <= 60]
            if len(precision_errs) > 0:
                mean_pe = sum(precision_errs) / len(precision_errs)
                variance = sum((x - mean_pe) ** 2 for x in precision_errs) / len(precision_errs)
                precision_sd = math.sqrt(variance)
            else:
                precision_sd = None
                
            results[pid][ss] = {
                'mae': mae,
                'guess_rate': guess_rate,
                'precision_sd': precision_sd
            }
            total_trials += len(errors)
            total_guesses += guesses
            
        overall_guess_rate = total_guesses / total_trials
        results[pid]['excluded'] = overall_guess_rate > 0.50
        
    group_means = {1: {'mae': [], 'guess_rate': [], 'precision_sd': []},
                   2: {'mae': [], 'guess_rate': [], 'precision_sd': []},
                   4: {'mae': [], 'guess_rate': [], 'precision_sd': []},
                   8: {'mae': [], 'guess_rate': [], 'precision_sd': []}}
                   
    for pid, sizes in results.items():
        if sizes['excluded']:
            continue
        for ss in [1, 2, 4, 8]:
            group_means[ss]['mae'].append(sizes[ss]['mae'])
            group_means[ss]['guess_rate'].append(sizes[ss]['guess_rate'])
            if sizes[ss]['precision_sd'] is not None:
                group_means[ss]['precision_sd'].append(sizes[ss]['precision_sd'])
                
    gt_group = {}
    for ss in [1, 2, 4, 8]:
        gt_group[str(ss)] = {
            'mae': sum(group_means[ss]['mae']) / len(group_means[ss]['mae']) if group_means[ss]['mae'] else 0,
            'guess_rate': sum(group_means[ss]['guess_rate']) / len(group_means[ss]['guess_rate']) if group_means[ss]['guess_rate'] else 0,
            'precision_sd': sum(group_means[ss]['precision_sd']) / len(group_means[ss]['precision_sd']) if group_means[ss]['precision_sd'] else 0
        }
        
    return results, gt_group

def verify_vwm_color_reproduction_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Compute ground truth dynamically from the CSV file
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    csv_path = csv_tmp.name
    csv_tmp.close()
    
    try:
        copy_from_env('/home/ga/pebl/data/color_wheel_data.csv', csv_path)
        gt_participants, gt_group = compute_gt(csv_path)
    except Exception as e:
        feedback_parts.append(f"[0] Failed to read/compute ground truth from CSV: {e}")
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(csv_path):
            os.unlink(csv_path)

    # 2. Extract agent report
    report = None
    report_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    report_path = report_tmp.name
    report_tmp.close()

    try:
        copy_from_env('/home/ga/pebl/analysis/vwm_report.json', report_path)
        with open(report_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/vwm_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(report_path):
            os.unlink(report_path)

    # 3. Check excluded participant (s99)
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
            excluded_list = report.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
        return False

    if is_excluded('s99'):
        score += 15
        feedback_parts.append('[+15] s99 correctly excluded (uniform random responding).')
    else:
        feedback_parts.append('[0] s99 not excluded despite overall guess rate > 50%.')

    # 4. Check Circular Math / MAE / Guess Rate / Precision SD
    mae_correct = 0
    proxy_correct = 0
    total_valid_ss = 0
    
    for pid, gt_data in gt_participants.items():
        if pid == 's99' or gt_data['excluded']:
            continue
            
        entry = part_map.get(pid)
        if entry is None or entry.get('excluded'):
            continue
            
        set_sizes = entry.get('set_sizes', {})
        for ss in [1, 2, 4, 8]:
            ss_str = str(ss)
            total_valid_ss += 1
            if ss_str in set_sizes:
                agent_ss = set_sizes[ss_str]
                
                # Check MAE (indicates correct circular math)
                mae = agent_ss.get('mae')
                if mae is not None:
                    try:
                        if abs(float(mae) - gt_data[ss]['mae']) <= 1.0:
                            mae_correct += 1
                    except (ValueError, TypeError):
                        pass
                        
                # Check Guess Rate
                gr = agent_ss.get('guess_rate')
                gr_ok = False
                if gr is not None:
                    try:
                        if abs(float(gr) - gt_data[ss]['guess_rate']) <= 0.05:
                            gr_ok = True
                    except (ValueError, TypeError):
                        pass
                        
                # Check Precision SD
                psd = agent_ss.get('precision_sd')
                psd_ok = False
                if psd is not None and gt_data[ss]['precision_sd'] is not None:
                    try:
                        if abs(float(psd) - gt_data[ss]['precision_sd']) <= 1.0:
                            psd_ok = True
                    except (ValueError, TypeError):
                        pass
                elif psd is None and gt_data[ss]['precision_sd'] is None:
                    psd_ok = True
                    
                if gr_ok and psd_ok:
                    proxy_correct += 1

    mae_pts = 0
    if total_valid_ss > 0:
        mae_ratio = mae_correct / total_valid_ss
        proxy_ratio = proxy_correct / total_valid_ss
        
        mae_pts = int(25 * mae_ratio)
        score += mae_pts
        feedback_parts.append(f'[+{mae_pts}] Circular Math / MAE correct for {mae_correct}/{total_valid_ss} conditions.')
        
        proxy_pts = int(30 * proxy_ratio)
        score += proxy_pts
        feedback_parts.append(f'[+{proxy_pts}] Guess Rate & Precision correct for {proxy_correct}/{total_valid_ss} conditions.')
    else:
        feedback_parts.append('[0] No valid set size data to grade participant metrics.')

    # 5. Check Group Means
    group_means = report.get('group_means', {})
    gm_correct = 0
    for ss in ['1', '2', '4', '8']:
        if ss in group_means and ss in gt_group:
            agent_gm = group_means[ss]
            gt_gm = gt_group[ss]
            
            mae_ok = False
            gr_ok = False
            psd_ok = False
            
            if agent_gm.get('mae') is not None:
                try:
                    if abs(float(agent_gm['mae']) - gt_gm['mae']) <= 1.0:
                        mae_ok = True
                except (ValueError, TypeError):
                    pass
                    
            if agent_gm.get('guess_rate') is not None:
                try:
                    if abs(float(agent_gm['guess_rate']) - gt_gm['guess_rate']) <= 0.05:
                        gr_ok = True
                except (ValueError, TypeError):
                    pass
                    
            if agent_gm.get('precision_sd') is not None:
                try:
                    if abs(float(agent_gm['precision_sd']) - gt_gm['precision_sd']) <= 1.0:
                        psd_ok = True
                except (ValueError, TypeError):
                    pass
                    
            if mae_ok and gr_ok and psd_ok:
                gm_correct += 1

    gm_pts = int(20 * (gm_correct / 4))
    score += gm_pts
    feedback_parts.append(f'[+{gm_pts}] Group means correct for {gm_correct}/4 set sizes.')

    passed = score >= 60 and mae_pts >= 15
    if score >= 60 and not passed:
        feedback_parts.append('[FAIL] Passed point threshold but failed circular math / MAE requirement.')

    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }