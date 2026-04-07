"""
Verifier for pm_cost_accuracy_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Automated participant sub-99 is excluded                      (25 pts)
  3. PM Cost accurate for >= 18 valid participants                 (30 pts)
  4. PM Hit Rate accurate for >= 18 valid participants             (20 pts)
  5. Group means accurately calculated                             (15 pts)

Pass threshold: 60 pts

The verifier copies both the agent's report and the original data file from the 
environment to calculate the absolute ground truth dynamically. This makes the 
verification 100% robust against any data generation variance.
"""

import json
import os
import csv
import tempfile
import statistics

CONTAMINATED_PARTICIPANT = 'sub-99'
PASS_THRESHOLD = 60
RT_TOLERANCE = 1.0     # ±1.0 ms tolerance for rounding
RATE_TOLERANCE = 0.02  # ±2% tolerance for hit rates
MIN_CORRECT_PPTS = 18

def compute_ground_truth(csv_path):
    """Dynamically computes the ground truth from the actual environment CSV."""
    data = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in data:
                data[pid] = {'baseline_ongoing': [], 'pm_ongoing': [], 'pm_cues': []}
            
            rt = float(row['rt_ms'])
            correct = int(row['correct'])
            b_type = row['block_type']
            t_type = row['trial_type']
            
            # Baseline Ongoing (Correct only)
            if b_type == 'baseline' and t_type == 'ongoing' and correct == 1:
                data[pid]['baseline_ongoing'].append(rt)
                
            # PM Block Ongoing (Correct only)
            elif b_type == 'pm_block' and t_type == 'ongoing' and correct == 1:
                data[pid]['pm_ongoing'].append(rt)
                
            # PM Block Cues (Accuracy)
            elif b_type == 'pm_block' and t_type == 'pm_cue':
                data[pid]['pm_cues'].append(correct)

    ground_truth = {}
    for pid, trials in data.items():
        if pid == CONTAMINATED_PARTICIPANT:
            continue
            
        base_rt = statistics.mean(trials['baseline_ongoing']) if trials['baseline_ongoing'] else 0.0
        pm_rt = statistics.mean(trials['pm_ongoing']) if trials['pm_ongoing'] else 0.0
        pm_cost = pm_rt - base_rt
        hit_rate = statistics.mean(trials['pm_cues']) if trials['pm_cues'] else 0.0
        
        ground_truth[pid] = {
            'baseline_ongoing_rt_ms': base_rt,
            'pm_block_ongoing_rt_ms': pm_rt,
            'pm_cost_ms': pm_cost,
            'pm_hit_rate': hit_rate
        }
        
    group_pm_cost = statistics.mean([gt['pm_cost_ms'] for gt in ground_truth.values()])
    group_hit_rate = statistics.mean([gt['pm_hit_rate'] for gt in ground_truth.values()])
    
    return ground_truth, group_pm_cost, group_hit_rate

def verify_pm_cost_accuracy_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # Ensure temp cleanup
    tmp_json_path = tempfile.mktemp(suffix='.json')
    tmp_csv_path = tempfile.mktemp(suffix='.csv')

    try:
        # 1. Fetch data file to compute ground truth dynamically
        copy_from_env('/home/ga/pebl/data/prospective_memory_data.csv', tmp_csv_path)
        ground_truth, group_cost_gt, group_rate_gt = compute_ground_truth(tmp_csv_path)
        
        # 2. Fetch agent's report
        try:
            copy_from_env('/home/ga/pebl/analysis/pm_report.json', tmp_json_path)
            with open(tmp_json_path, 'r', encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append('[+10] Output file found and is valid JSON.')
        except FileNotFoundError:
            feedback_parts.append('[0] Output file /home/ga/pebl/analysis/pm_report.json not found.')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
        except (json.JSONDecodeError, ValueError) as e:
            feedback_parts.append(f'[0] Output file not valid JSON: {e}')
            return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

        # Build lookup maps
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
            excluded_list = report.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
            return False

        # --- Criterion 2: sub-99 excluded ---
        if is_excluded(CONTAMINATED_PARTICIPANT):
            score += 25
            feedback_parts.append(f'[+25] {CONTAMINATED_PARTICIPANT} correctly excluded (Automated responder).')
        else:
            feedback_parts.append(f'[0] {CONTAMINATED_PARTICIPANT} not excluded despite impossible RTs.')

        # --- Criterion 3 & 4: PM Cost & PM Hit Rate Accuracy ---
        correct_pm_cost = 0
        correct_hit_rate = 0
        
        for pid, gt_vals in ground_truth.items():
            entry = part_map.get(pid)
            if entry is None or is_excluded(pid):
                continue
                
            # Check PM Cost
            agent_cost = entry.get('pm_cost_ms') or entry.get('pm_cost')
            if agent_cost is not None:
                try:
                    if abs(float(agent_cost) - gt_vals['pm_cost_ms']) <= RT_TOLERANCE:
                        correct_pm_cost += 1
                except (TypeError, ValueError):
                    pass
                    
            # Check PM Hit Rate
            agent_rate = entry.get('pm_hit_rate') or entry.get('hit_rate')
            if agent_rate is not None:
                try:
                    if abs(float(agent_rate) - gt_vals['pm_hit_rate']) <= RATE_TOLERANCE:
                        correct_hit_rate += 1
                except (TypeError, ValueError):
                    pass

        # Score Criterion 3
        if correct_pm_cost >= MIN_CORRECT_PPTS:
            score += 30
            feedback_parts.append(f'[+30] PM Cost correct for {correct_pm_cost}/20 valid participants.')
        elif correct_pm_cost >= 5:
            partial = 15
            score += partial
            feedback_parts.append(f'[+{partial}] PM Cost correct for {correct_pm_cost}/20 participants (partial).')
        else:
            feedback_parts.append(f'[0] PM Cost correct for only {correct_pm_cost}/20 valid participants.')

        # Score Criterion 4
        if correct_hit_rate >= MIN_CORRECT_PPTS:
            score += 20
            feedback_parts.append(f'[+20] PM Hit Rate correct for {correct_hit_rate}/20 valid participants.')
        elif correct_hit_rate >= 5:
            partial = 10
            score += partial
            feedback_parts.append(f'[+{partial}] PM Hit Rate correct for {correct_hit_rate}/20 participants (partial).')
        else:
            feedback_parts.append(f'[0] PM Hit Rate correct for only {correct_hit_rate}/20 valid participants.')

        # --- Criterion 5: Group Means ---
        agent_group_cost = report.get('group_mean_pm_cost_ms') or report.get('group_pm_cost')
        agent_group_rate = report.get('group_mean_pm_hit_rate') or report.get('group_hit_rate')
        
        group_pts = 0
        if agent_group_cost is not None:
            try:
                if abs(float(agent_group_cost) - group_cost_gt) <= RT_TOLERANCE:
                    group_pts += 8
            except (TypeError, ValueError):
                pass
                
        if agent_group_rate is not None:
            try:
                if abs(float(agent_group_rate) - group_rate_gt) <= RATE_TOLERANCE:
                    group_pts += 7
            except (TypeError, ValueError):
                pass
                
        if group_pts == 15:
            score += 15
            feedback_parts.append('[+15] Group mean PM Cost and Hit Rate are both accurate.')
        elif group_pts > 0:
            score += group_pts
            feedback_parts.append(f'[+{group_pts}] Group means partially accurate.')
        else:
            feedback_parts.append('[0] Group means missing or inaccurate.')

    finally:
        for p in [tmp_json_path, tmp_csv_path]:
            if os.path.exists(p):
                try:
                    os.unlink(p)
                except Exception:
                    pass

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }