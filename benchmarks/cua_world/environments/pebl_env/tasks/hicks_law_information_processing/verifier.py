#!/usr/bin/env python3
"""
Verifier for hicks_law_information_processing task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Corrupted participant sub-99 is excluded (accuracy < 60%)     (20 pts)
  3. Mean RT aggregation correct for >= 80% of valid participants  (25 pts)
  4. Regression (slope/intercept) correct for >= 80% valid ppts    (30 pts)
  5. Group means for slope and intercept are correct               (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile

def verify_hicks_law_information_processing(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    score = 0
    feedback_parts = []
    
    # 1. Check if Output exists and is valid
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        report_path = tmp.name
        
    try:
        copy_from_env('/home/ga/pebl/analysis/hicks_report.json', report_path)
        with open(report_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except Exception as e:
        feedback_parts.append(f'[0] Output file /home/ga/pebl/analysis/hicks_report.json not found or invalid: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback_parts)}
    finally:
        if os.path.exists(report_path):
            os.unlink(report_path)
            
    # Load dynamically generated ground truth
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        gt_path = tmp.name
        
    try:
        copy_from_env('/tmp/hicks_ground_truth.json', gt_path)
        with open(gt_path, encoding='utf-8') as f:
            gt = json.load(f)
    except Exception as e:
        feedback_parts.append(f'Failed to load ground truth: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback_parts)}
    finally:
        if os.path.exists(gt_path):
            os.unlink(gt_path)
            
    # Build maps
    participants_list = report.get('participants', [])
    part_map = {}
    if isinstance(participants_list, list):
        for entry in participants_list:
            if isinstance(entry, dict):
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
        
    # 2. Exclude sub-99
    if is_excluded("sub-99"):
        score += 20
        feedback_parts.append('[+20] sub-99 correctly excluded (accuracy < 60%).')
    else:
        feedback_parts.append('[0] sub-99 not excluded despite poor accuracy.')
        
    # 3. Aggregation and 4. Regression checks
    correct_rt_agg = 0
    correct_reg = 0
    gt_participants = gt.get('participants', {})
    
    for pid, gt_p in gt_participants.items():
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
            
        # Check RT Aggregation
        mean_rt = entry.get('mean_rt_by_n', {})
        if isinstance(mean_rt, dict) and len(mean_rt) > 0:
            agg_ok = True
            for n_val in ['1', '2', '4', '8']:
                val = mean_rt.get(n_val) or mean_rt.get(int(n_val))
                if val is not None:
                    try:
                        if abs(float(val) - gt_p['mean_rt_by_n'][n_val]) > 2.0:
                            agg_ok = False
                    except:
                        agg_ok = False
                else:
                    agg_ok = False
            if agg_ok:
                correct_rt_agg += 1
                
        # Check Regression Calculations
        slope = entry.get('hicks_slope_ms_per_bit') or entry.get('slope') or entry.get('hicks_slope')
        intercept = entry.get('hicks_intercept_ms') or entry.get('intercept') or entry.get('hicks_intercept')
        
        if slope is not None and intercept is not None:
            try:
                s_diff = abs(float(slope) - gt_p['slope'])
                i_diff = abs(float(intercept) - gt_p['intercept'])
                # Allow a generous 1.0 ms tolerance for float precision rounding
                if s_diff <= 1.0 and i_diff <= 1.0:
                    correct_reg += 1
            except:
                pass
                
    # Score 3: Mean RT Aggregation
    if correct_rt_agg >= 16:
        score += 25
        feedback_parts.append(f'[+25] Mean RT aggregation correct for {correct_rt_agg}/20 valid participants.')
    elif correct_rt_agg >= 10:
        score += 12
        feedback_parts.append(f'[+12] Mean RT aggregation correct for {correct_rt_agg}/20 participants (partial credit).')
    else:
        feedback_parts.append(f'[0] Mean RT aggregation correct for only {correct_rt_agg}/20 participants.')
        
    # Score 4: Hick's Law Linear Regression
    if correct_reg >= 16:
        score += 30
        feedback_parts.append(f'[+30] Hick\'s Law regression (slope/intercept) correct for {correct_reg}/20 participants.')
    elif correct_reg >= 10:
        score += 15
        feedback_parts.append(f'[+15] Hick\'s Law regression correct for {correct_reg}/20 participants (partial credit).')
    else:
        feedback_parts.append(f'[0] Hick\'s Law regression correct for only {correct_reg}/20 participants.')
        
    # 5. Group means validation
    g_slope = report.get('group_mean_slope')
    g_intercept = report.get('group_mean_intercept')
    
    group_ok = 0
    if g_slope is not None:
        try:
            if abs(float(g_slope) - gt['group_mean_slope']) <= 1.0:
                group_ok += 1
        except:
            pass
            
    if g_intercept is not None:
        try:
            if abs(float(g_intercept) - gt['group_mean_intercept']) <= 1.0:
                group_ok += 1
        except:
            pass
            
    if group_ok == 2:
        score += 15
        feedback_parts.append('[+15] Group means for slope and intercept are correct.')
    elif group_ok == 1:
        score += 7
        feedback_parts.append('[+7] Group means partially correct.')
    else:
        feedback_parts.append('[0] Group means incorrect or missing.')
        
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }