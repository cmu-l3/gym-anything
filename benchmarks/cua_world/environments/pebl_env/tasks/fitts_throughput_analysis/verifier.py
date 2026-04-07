"""
Verifier for fitts_throughput_analysis task.

Scoring (100 pts total):
  1. Valid JSON output file                                        (10 pts)
  2. P99 correctly excluded (auto-clicker)                         (20 pts)
  3. All 15 valid participants present                             (10 pts)
  4. Individual throughput within ±0.5 bps for ≥12/15 ppts         (20 pts)
  5. Individual R² within ±0.10 for ≥12/15 ppts                    (10 pts)
  6. Group mean throughput within ±0.35 bps                        (15 pts)
  7. Group mean slope within ±20 ms/bit                            (10 pts)
  8. Group mean R² within ±0.06                                    (5 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import csv
import math
from collections import defaultdict

CONTAMINATED = 'P99'
PASS_THRESHOLD = 60
TOL_TP = 0.5
TOL_R2 = 0.10
TOL_GRP_TP = 0.35
TOL_GRP_SLOPE = 20.0
TOL_GRP_R2 = 0.06

def compute_fitts_ground_truth(csv_path):
    """Computes exact ISO 9241-411 Fitts metrics from the CSV data."""
    # data[pid][(a, w)] = {'mt': [], 'dx': []}
    data = defaultdict(lambda: defaultdict(lambda: {'mt': [], 'dx': []}))
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant']
            a = float(row['amplitude'])
            w = float(row['width'])
            data[pid][(a, w)]['mt'].append(float(row['mt_ms']))
            data[pid][(a, w)]['dx'].append(float(row['dx']))

    results = {}
    for pid, conditions in data.items():
        pts = []
        tps = []
        
        for (a, w), trials in conditions.items():
            if len(trials['mt']) == 0:
                continue
            mean_mt = sum(trials['mt']) / len(trials['mt'])
            dxs = trials['dx']
            mean_dx = sum(dxs) / len(dxs)
            
            # Sample variance (n-1)
            n = len(dxs)
            variance = sum((x - mean_dx)**2 for x in dxs) / (n - 1) if n > 1 else 0
            sdx = math.sqrt(variance)
            We = 4.133 * sdx
            
            if We <= 0:
                IDe = math.log2(2 * a / w)
            else:
                IDe = math.log2(2 * a / We)
                
            if IDe > 0 and mean_mt > 0:
                pts.append((IDe, mean_mt))
                tps.append(IDe / (mean_mt / 1000.0))
                
        if len(pts) < 2:
            continue
            
        # Linear Regression: MT = a + b * IDe
        mean_x = sum(x for x, y in pts) / len(pts)
        mean_y = sum(y for x, y in pts) / len(pts)
        
        num = sum((x - mean_x) * (y - mean_y) for x, y in pts)
        den = sum((x - mean_x)**2 for x, y in pts)
        
        if den == 0:
            continue
            
        slope = num / den
        intercept = mean_y - slope * mean_x
        
        # R-squared
        ss_tot = sum((y - mean_y)**2 for x, y in pts)
        ss_res = sum((y - (intercept + slope * x))**2 for x, y in pts)
        r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 0
        
        mean_tp = sum(tps) / len(tps)
        
        results[pid] = {
            'throughput_bps': mean_tp,
            'slope_ms_per_bit': slope,
            'intercept_ms': intercept,
            'r_squared': r_squared
        }
        
    return results

def verify_fitts_throughput_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []
    
    # 1. Fetch CSV data to calculate ground truth
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False).name
    try:
        copy_from_env('/tmp/fitts_data_copy.csv', csv_tmp)
        ground_truth = compute_fitts_ground_truth(csv_tmp)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f"Failed to compute ground truth from data: {e}"}
    finally:
        if os.path.exists(csv_tmp):
            os.unlink(csv_tmp)

    # Calculate GT group means
    valid_gts = [gt for pid, gt in ground_truth.items() if pid != CONTAMINATED]
    if not valid_gts:
        return {'passed': False, 'score': 0, 'feedback': "Ground truth failed to find valid participants."}
        
    gt_group_tp = sum(gt['throughput_bps'] for gt in valid_gts) / len(valid_gts)
    gt_group_slope = sum(gt['slope_ms_per_bit'] for gt in valid_gts) / len(valid_gts)
    gt_group_r2 = sum(gt['r_squared'] for gt in valid_gts) / len(valid_gts)

    # 2. Fetch Report JSON
    report = None
    json_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False).name
    try:
        copy_from_env('/home/ga/pebl/analysis/fitts_report.json', json_tmp)
        with open(json_tmp, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file /home/ga/pebl/analysis/fitts_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file is not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(json_tmp):
            os.unlink(json_tmp)

    part_map = {}
    for entry in report.get('participants', []):
        pid = entry.get('id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        return entry and entry.get('excluded') in (True, 'true', 1, 'yes')

    # Criterion 2: P99 excluded
    if is_excluded(CONTAMINATED):
        score += 20
        feedback_parts.append(f'[+20] {CONTAMINATED} correctly excluded.')
    else:
        feedback_parts.append(f'[0] {CONTAMINATED} not excluded.')

    # Criterion 3: 15 valid participants present
    valid_pids = [f"P{p:02d}" for p in range(1, 16)]
    present_valid = [p for p in valid_pids if p in part_map and not is_excluded(p)]
    
    if len(present_valid) == 15:
        score += 10
        feedback_parts.append('[+10] All 15 valid participants present.')
    else:
        feedback_parts.append(f'[0] Only {len(present_valid)}/15 valid participants present.')

    # Criterion 4 & 5: Individual TP and R2
    correct_tp = 0
    correct_r2 = 0
    
    for pid in present_valid:
        entry = part_map[pid]
        gt = ground_truth.get(pid)
        if not gt:
            continue
            
        tp = entry.get('throughput_bps') or entry.get('throughput')
        if tp is not None:
            try:
                if abs(float(tp) - gt['throughput_bps']) <= TOL_TP:
                    correct_tp += 1
            except (ValueError, TypeError): pass

        r2 = entry.get('r_squared') or entry.get('r2')
        if r2 is not None:
            try:
                if abs(float(r2) - gt['r_squared']) <= TOL_R2:
                    correct_r2 += 1
            except (ValueError, TypeError): pass

    if correct_tp >= 12:
        score += 20
        feedback_parts.append(f'[+20] TP accurate for {correct_tp}/15 participants.')
    elif correct_tp >= 6:
        score += 10
        feedback_parts.append(f'[+10] TP accurate for {correct_tp}/15 participants (partial).')
    else:
        feedback_parts.append(f'[0] TP accurate for {correct_tp}/15 participants.')

    if correct_r2 >= 12:
        score += 10
        feedback_parts.append(f'[+10] R² accurate for {correct_r2}/15 participants.')
    elif correct_r2 >= 6:
        score += 5
        feedback_parts.append(f'[+5] R² accurate for {correct_r2}/15 participants (partial).')
    else:
        feedback_parts.append(f'[0] R² accurate for {correct_r2}/15 participants.')

    # Group Means
    rep_tp = report.get('group_mean_throughput_bps') or report.get('group_mean_throughput')
    rep_slope = report.get('group_mean_slope_ms_per_bit') or report.get('group_mean_slope')
    rep_r2 = report.get('group_mean_r_squared') or report.get('group_mean_r2')

    if rep_tp is not None:
        try:
            if abs(float(rep_tp) - gt_group_tp) <= TOL_GRP_TP:
                score += 15
                feedback_parts.append('[+15] Group TP accurate.')
            else:
                feedback_parts.append(f'[0] Group TP {rep_tp} outside tolerance (expected {gt_group_tp:.2f}).')
        except (ValueError, TypeError):
            feedback_parts.append('[0] Group TP invalid format.')
    else:
        feedback_parts.append('[0] Group TP missing.')

    if rep_slope is not None:
        try:
            if abs(float(rep_slope) - gt_group_slope) <= TOL_GRP_SLOPE:
                score += 10
                feedback_parts.append('[+10] Group Slope accurate.')
            else:
                feedback_parts.append(f'[0] Group Slope {rep_slope} outside tol (expected {gt_group_slope:.1f}).')
        except (ValueError, TypeError):
            feedback_parts.append('[0] Group Slope invalid format.')
    else:
        feedback_parts.append('[0] Group Slope missing.')

    if rep_r2 is not None:
        try:
            if abs(float(rep_r2) - gt_group_r2) <= TOL_GRP_R2:
                score += 5
                feedback_parts.append('[+5] Group R² accurate.')
            else:
                feedback_parts.append(f'[0] Group R² {rep_r2} outside tol (expected {gt_group_r2:.2f}).')
        except (ValueError, TypeError):
            feedback_parts.append('[0] Group R² invalid format.')
    else:
        feedback_parts.append('[0] Group R² missing.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }