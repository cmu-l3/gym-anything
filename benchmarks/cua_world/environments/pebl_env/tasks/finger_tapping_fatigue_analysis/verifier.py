#!/usr/bin/env python3
"""
Verifier for finger_tapping_fatigue_analysis task.
"""

import json
import os
import tempfile
import csv
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_finger_tapping_fatigue_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 0. Check anti-gaming
    result_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    result_tmp_path = result_tmp.name
    result_tmp.close()
    try:
        copy_from_env('/tmp/task_result.json', result_tmp_path)
        with open(result_tmp_path, encoding='utf-8') as f:
            export_data = json.load(f)
            
        if export_data.get('output_exists') and not export_data.get('file_created_during_task', False):
            return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: output file was not created or modified during the task."}
    except Exception as e:
        logger.warning(f"Could not verify timestamps: {e}")
    finally:
        if os.path.exists(result_tmp_path):
            os.unlink(result_tmp_path)

    # 1. Get the generated CSV to compute Ground Truth dynamically
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    csv_tmp_path = csv_tmp.name
    csv_tmp.close()

    try:
        copy_from_env('/home/ga/pebl/data/ftt_tapping_data.csv', csv_tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to get data file from env: {e}"}

    participants_data = {}
    with open(csv_tmp_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        trials = {}
        for row in reader:
            pid = row['participant_id']
            hand = row['hand']
            trial = row['trial']
            
            key = (pid, hand, trial)
            if key not in trials:
                trials[key] = []
            trials[key].append(row)
            
    for (pid, hand, trial), taps in trials.items():
        if pid not in participants_data:
            participants_data[pid] = {'dom_hz': [], 'nondom_hz': [], 'dom_fi': [], 'dom_cv': []}
            
        total_taps = len(taps)
        hz = total_taps / 10.0
        
        if hand == 'Dominant':
            participants_data[pid]['dom_hz'].append(hz)
            first_half = sum(1 for t in taps if float(t['tap_time_ms']) <= 5000.0)
            second_half = sum(1 for t in taps if float(t['tap_time_ms']) > 5000.0)
            fi = second_half / first_half if first_half > 0 else 0
            participants_data[pid]['dom_fi'].append(fi)
            
            itis = [float(t['iti_ms']) for t in taps if str(t['iti_ms']) != 'NA' and int(t['tap_number']) > 1]
            if len(itis) > 1:
                mean_iti = sum(itis) / len(itis)
                var_sample = sum((x - mean_iti)**2 for x in itis) / (len(itis) - 1)
                var_pop = sum((x - mean_iti)**2 for x in itis) / len(itis)
                cv_sample = math.sqrt(var_sample) / mean_iti if mean_iti > 0 else 0
                cv_pop = math.sqrt(var_pop) / mean_iti if mean_iti > 0 else 0
                participants_data[pid]['dom_cv'].append((cv_sample, cv_pop))
            else:
                participants_data[pid]['dom_cv'].append((0.0, 0.0))
        else:
            participants_data[pid]['nondom_hz'].append(hz)
            
    gt = {}
    for pid, data in participants_data.items():
        dom_hz = sum(data['dom_hz']) / len(data['dom_hz']) if data['dom_hz'] else 0
        nondom_hz = sum(data['nondom_hz']) / len(data['nondom_hz']) if data['nondom_hz'] else 0
        dom_fi = sum(data['dom_fi']) / len(data['dom_fi']) if data['dom_fi'] else 0
        
        cv_samples = [c[0] for c in data['dom_cv']]
        cv_pops = [c[1] for c in data['dom_cv']]
        
        dom_cv_sample = sum(cv_samples) / len(cv_samples) if cv_samples else 0
        dom_cv_pop = sum(cv_pops) / len(cv_pops) if cv_pops else 0
        
        gt[pid] = {
            'dom_hz': dom_hz,
            'nondom_hz': nondom_hz,
            'dom_fi': dom_fi,
            'dom_cv_sample': dom_cv_sample,
            'dom_cv_pop': dom_cv_pop
        }

    valid_pids = [p for p in gt if p != 'P099']
    gt_group_means = {
        'mean_dominant_hz': sum(gt[p]['dom_hz'] for p in valid_pids) / len(valid_pids),
        'mean_nondominant_hz': sum(gt[p]['nondom_hz'] for p in valid_pids) / len(valid_pids),
        'mean_fatigue_index': sum(gt[p]['dom_fi'] for p in valid_pids) / len(valid_pids),
        'mean_cv_sample': sum(gt[p]['dom_cv_sample'] for p in valid_pids) / len(valid_pids),
        'mean_cv_pop': sum(gt[p]['dom_cv_pop'] for p in valid_pids) / len(valid_pids)
    }

    # 2. Get agent report
    report_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    report_tmp_path = report_tmp.name
    report_tmp.close()

    score = 0
    feedback_parts = []
    try:
        copy_from_env('/home/ga/pebl/analysis/ftt_fatigue_report.json', report_tmp_path)
        with open(report_tmp_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Report is valid JSON")
    except Exception as e:
        feedback_parts.append(f"[0] Failed to load JSON report: {e}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(csv_tmp_path):
            os.unlink(csv_tmp_path)
        if os.path.exists(report_tmp_path):
            os.unlink(report_tmp_path)

    # 3. Check macro exclusion
    participants = report.get('participants', [])
    part_dict = {}
    for p in participants:
        pid = p.get('id') or p.get('participant_id') or p.get('participant')
        if pid:
            part_dict[str(pid)] = p

    p099 = part_dict.get('P099')
    is_excluded = False
    if p099 and (p099.get('excluded') in [True, 'true', 1]):
        is_excluded = True
    elif 'P099' not in part_dict and 'P099' in report.get('excluded', []):
        is_excluded = True
        
    if is_excluded:
        score += 20
        feedback_parts.append("[+20] P099 correctly excluded")
    else:
        feedback_parts.append("[0] P099 not excluded")

    # 4. Check participant accuracy
    hz_correct = 0
    fi_correct = 0
    cv_correct = 0

    for pid in valid_pids:
        p_data = part_dict.get(pid)
        if not p_data or p_data.get('excluded'):
            continue
            
        dom_hz = p_data.get('dominant_hz', -1)
        nondom_hz = p_data.get('nondominant_hz', -1)
        dom_fi = p_data.get('dominant_fatigue_index', -1)
        dom_cv = p_data.get('dominant_cv', -1)
        
        try:
            dom_hz = float(dom_hz)
            nondom_hz = float(nondom_hz)
            dom_fi = float(dom_fi)
            dom_cv = float(dom_cv)
            
            if abs(dom_hz - gt[pid]['dom_hz']) <= 0.05 and abs(nondom_hz - gt[pid]['nondom_hz']) <= 0.05:
                hz_correct += 1
                
            if abs(dom_fi - gt[pid]['dom_fi']) <= 0.02:
                fi_correct += 1
                
            if abs(dom_cv - gt[pid]['dom_cv_sample']) <= 0.015 or abs(dom_cv - gt[pid]['dom_cv_pop']) <= 0.015:
                cv_correct += 1
        except (ValueError, TypeError):
            pass

    if hz_correct >= 19:
        score += 20
        feedback_parts.append(f"[+20] Hz accurate for {hz_correct}/21 participants")
    else:
        feedback_parts.append(f"[0] Hz accurate for {hz_correct}/21 participants (need 19)")

    if fi_correct >= 19:
        score += 20
        feedback_parts.append(f"[+20] FI accurate for {fi_correct}/21 participants")
    else:
        feedback_parts.append(f"[0] FI accurate for {fi_correct}/21 participants (need 19)")

    if cv_correct >= 19:
        score += 15
        feedback_parts.append(f"[+15] CV accurate for {cv_correct}/21 participants")
    else:
        feedback_parts.append(f"[0] CV accurate for {cv_correct}/21 participants (need 19)")

    # 5. Check group statistics
    group_stats = report.get('group_statistics', {})
    if group_stats:
        try:
            mean_dom_hz = float(group_stats.get('mean_dominant_hz', -1))
            mean_nondom_hz = float(group_stats.get('mean_nondominant_hz', -1))
            mean_fi = float(group_stats.get('mean_fatigue_index', -1))
            mean_cv = float(group_stats.get('mean_cv', -1))
            
            hz_ok = abs(mean_dom_hz - gt_group_means['mean_dominant_hz']) <= 0.05 and abs(mean_nondom_hz - gt_group_means['mean_nondominant_hz']) <= 0.05
            fi_ok = abs(mean_fi - gt_group_means['mean_fatigue_index']) <= 0.05
            cv_ok = abs(mean_cv - gt_group_means['mean_cv_sample']) <= 0.02 or abs(mean_cv - gt_group_means['mean_cv_pop']) <= 0.02
            
            if hz_ok and fi_ok and cv_ok and is_excluded:
                score += 15
                feedback_parts.append("[+15] Group statistics accurate")
            else:
                feedback_parts.append("[0] Group statistics inaccurate or polluted by P099")
        except (ValueError, TypeError):
            feedback_parts.append("[0] Group statistics missing or malformed")
    else:
        feedback_parts.append("[0] Missing group_statistics")

    passed = score >= 65 and is_excluded
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }