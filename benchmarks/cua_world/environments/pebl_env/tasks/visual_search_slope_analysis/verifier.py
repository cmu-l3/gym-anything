#!/usr/bin/env python3
import json
import os
import tempfile
import csv

def compute_ground_truth(csv_path):
    """Dynamically parses the generated CSV to calculate the exact OLS linear regression ground truth."""
    data = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)
            
    # Calculate Target Present Accuracy
    tp_totals = {}
    tp_corrects = {}
    for row in data:
        pid = row['participant_id']
        tp = int(row['target_present'])
        correct = int(row['response_correct'])
        
        if pid not in tp_totals:
            tp_totals[pid] = 0
            tp_corrects[pid] = 0
            
        if tp == 1:
            tp_totals[pid] += 1
            tp_corrects[pid] += correct
            
    valid_ppts = set()
    excluded_ppts = set()
    for pid in tp_totals:
        acc = tp_corrects[pid] / tp_totals[pid] if tp_totals[pid] > 0 else 0
        if acc < 0.20:
            excluded_ppts.add(pid)
        else:
            valid_ppts.add(pid)
            
    # Compile RTs (Correct responses only!)
    rt_sums = {}
    rt_counts = {}
    
    for row in data:
        pid = row['participant_id']
        if pid not in valid_ppts:
            continue
            
        if int(row['response_correct']) == 0:
            continue
            
        cond = row['condition']
        tp = int(row['target_present'])
        sz = int(row['set_size'])
        rt = float(row['rt_ms'])
        
        cond_name = f"{cond}_present" if tp == 1 else f"{cond}_absent"
        
        key = (pid, cond_name, sz)
        rt_sums[key] = rt_sums.get(key, 0) + rt
        rt_counts[key] = rt_counts.get(key, 0) + 1
        
    means = {}
    for key in rt_sums:
        means[key] = rt_sums[key] / rt_counts[key]
        
    points = {}
    for (pid, cond_name, sz), mean_rt in means.items():
        if pid not in points:
            points[pid] = {}
        if cond_name not in points[pid]:
            points[pid][cond_name] = {'x': [], 'y': []}
        points[pid][cond_name]['x'].append(sz)
        points[pid][cond_name]['y'].append(mean_rt)
        
    # Manual OLS Linear Regression Computation 
    slopes = {}
    for pid, conds in points.items():
        slopes[pid] = {}
        for cond_name, vals in conds.items():
            x = vals['x']
            y = vals['y']
            n = len(x)
            if n < 2:
                slopes[pid][cond_name] = 0.0
                continue
            sum_x = sum(x)
            sum_y = sum(y)
            sum_xy = sum(i*j for i,j in zip(x, y))
            sum_x2 = sum(i**2 for i in x)
            denominator = (n * sum_x2 - sum_x**2)
            slope = (n * sum_xy - sum_x * sum_y) / denominator if denominator != 0 else 0
            slopes[pid][cond_name] = round(slope, 1)
            
    # Group mean slopes
    group_slopes = {}
    cond_names = ['feature_present', 'feature_absent', 'conjunction_present', 'conjunction_absent']
    for cond_name in cond_names:
        cond_slopes = [slopes[pid].get(cond_name, 0) for pid in valid_ppts if cond_name in slopes[pid]]
        if cond_slopes:
            group_slopes[cond_name] = round(sum(cond_slopes) / len(cond_slopes), 1)
        else:
            group_slopes[cond_name] = 0.0
            
    return valid_ppts, excluded_ppts, slopes, group_slopes

def verify_visual_search_slope_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []
    
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        csv_path = tmp_csv.name
        
    try:
        copy_from_env('/home/ga/pebl/data/visual_search_data.csv', csv_path)
        valid_ppts, excluded_ppts, gt_slopes, gt_group_slopes = compute_ground_truth(csv_path)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Failed to process ground truth data: {e}'}
    finally:
        if os.path.exists(csv_path):
            os.unlink(csv_path)

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_json:
        json_path = tmp_json.name
        
    try:
        copy_from_env('/home/ga/pebl/analysis/visual_search_report.json', json_path)
        with open(json_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        return {'passed': False, 'score': 0, 'feedback': 'Output file not found.'}
    except (json.JSONDecodeError, ValueError) as e:
        return {'passed': False, 'score': 0, 'feedback': f'Output file is not valid JSON: {e}'}
    finally:
        if os.path.exists(json_path):
            os.unlink(json_path)
            
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

    if is_excluded('sub-99'):
        score += 20
        feedback_parts.append('[+20] sub-99 correctly excluded.')
    else:
        feedback_parts.append('[0] sub-99 not excluded.')

    correct_slopes_count = 0
    total_expected = len(valid_ppts) * 4
    
    for pid in valid_ppts:
        entry = part_map.get(pid)
        if not entry or is_excluded(pid):
            continue
        
        reported_slopes = entry.get('slopes_ms_per_item', {})
        gt = gt_slopes.get(pid, {})
        
        for cond in ['feature_present', 'feature_absent', 'conjunction_present', 'conjunction_absent']:
            rep_val = reported_slopes.get(cond)
            gt_val = gt.get(cond)
            if rep_val is not None and gt_val is not None:
                try:
                    if abs(float(rep_val) - gt_val) <= 1.0:
                        correct_slopes_count += 1
                except:
                    pass
                    
    # Error filtering is tested implicitly here. If the agent failed to filter response_correct==0, 
    # their computed slopes would be significantly outside the strict +/- 1.0 margin.
    if correct_slopes_count >= total_expected * 0.9:
        score += 50
        feedback_parts.append(f'[+50] Participant slopes correct ({correct_slopes_count}/{total_expected}). Error trials correctly filtered.')
    elif correct_slopes_count >= total_expected * 0.5:
        score += 25
        feedback_parts.append(f'[+25] Participant slopes partially correct ({correct_slopes_count}/{total_expected}).')
    else:
        feedback_parts.append(f'[0] Participant slopes incorrect or missing ({correct_slopes_count}/{total_expected}).')
        
    group_means = report.get('group_mean_slopes', report.get('group_means', {}))
    correct_group = 0
    for cond in ['feature_present', 'feature_absent', 'conjunction_present', 'conjunction_absent']:
        rep_val = group_means.get(cond)
        gt_val = gt_group_slopes.get(cond)
        if rep_val is not None and gt_val is not None:
            try:
                if abs(float(rep_val) - gt_val) <= 0.5:
                    correct_group += 1
            except:
                pass
                
    if correct_group == 4:
        score += 20
        feedback_parts.append('[+20] All 4 group mean slopes correct.')
    elif correct_group > 0:
        score += correct_group * 5
        feedback_parts.append(f'[+{correct_group * 5}] {correct_group}/4 group mean slopes correct.')
    else:
        feedback_parts.append('[0] Group mean slopes incorrect.')
        
    passed = score >= 70
    return {'passed': passed, 'score': score, 'feedback': ' '.join(feedback_parts)}