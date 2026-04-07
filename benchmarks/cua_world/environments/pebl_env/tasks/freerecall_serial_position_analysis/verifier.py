"""
Verifier for freerecall_serial_position_analysis task.

Since the dataset is uniquely generated per run (anti-gaming), the verifier 
dynamically computes the ground truth by parsing the agent's input CSV.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Contaminated participant (sub-999) is flagged/excluded        (20 pts)
  3. Exactly 30 valid participants analyzed                        (15 pts)
  4. Individual metrics (primacy, middle, recency, overall) match  (30 pts)
  5. Group serial position curve matches (15 positional means)     (25 pts)

Pass threshold: 60 pts
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED_ID = "sub-999"
TOLERANCE = 0.02

def compute_ground_truth(csv_path):
    """Computes exact ground truth directly from the randomly generated CSV."""
    data = {}
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            pos = int(row['study_position'])
            recalled = int(row['recalled'])
            rt = int(row['recall_rt_ms'])
            
            if pid not in data:
                data[pid] = {'trials': []}
            data[pid]['trials'].append({'pos': pos, 'recalled': recalled, 'rt': rt})
            
    gt_scores = {}
    valid_participants = []
    
    # Process individual participants
    for pid, pdata in data.items():
        trials = pdata['trials']
        total_trials = len(trials)
        if total_trials == 0: continue
            
        overall_recall = sum(t['recalled'] for t in trials) / total_trials
        mean_rt = sum(t['rt'] for t in trials) / total_trials
        
        # Check exclusion criteria
        is_excluded = (overall_recall == 0.0 and mean_rt < 50.0)
        
        if is_excluded:
            gt_scores[pid] = {'excluded': True}
        else:
            valid_participants.append(pid)
            # Primacy (1,2,3)
            primacy_trials = [t['recalled'] for t in trials if t['pos'] in (1, 2, 3)]
            primacy_score = sum(primacy_trials) / len(primacy_trials) if primacy_trials else 0.0
            
            # Middle (4 through 12)
            middle_trials = [t['recalled'] for t in trials if 4 <= t['pos'] <= 12]
            middle_score = sum(middle_trials) / len(middle_trials) if middle_trials else 0.0
            
            # Recency (13,14,15)
            recency_trials = [t['recalled'] for t in trials if t['pos'] in (13, 14, 15)]
            recency_score = sum(recency_trials) / len(recency_trials) if recency_trials else 0.0
            
            gt_scores[pid] = {
                'excluded': False,
                'primacy_score': primacy_score,
                'middle_score': middle_score,
                'recency_score': recency_score,
                'overall_recall': overall_recall
            }
            
    # Compute Group Serial Position Curve (15 positions)
    gt_curve = [0.0] * 15
    for pos in range(1, 16):
        pos_recalls = []
        for pid in valid_participants:
            pts = [t['recalled'] for t in data[pid]['trials'] if t['pos'] == pos]
            if pts:
                pos_recalls.append(sum(pts) / len(pts))
        
        if pos_recalls:
            gt_curve[pos-1] = sum(pos_recalls) / len(pos_recalls)
            
    return gt_scores, gt_curve, len(valid_participants)


def verify_freerecall_serial_position_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Fetch CSV and calculate GT
    csv_tmp = tempfile.NamedTemporaryFile(suffix='.csv', delete=False)
    json_tmp = tempfile.NamedTemporaryFile(suffix='.json', delete=False)
    
    try:
        try:
            copy_from_env('/home/ga/pebl/data/freerecall_data.csv', csv_tmp.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve CSV data: {e}"}
            
        gt_scores, gt_curve, num_valid_gt = compute_ground_truth(csv_tmp.name)
        
        # 2. Fetch Agent JSON
        try:
            copy_from_env('/home/ga/pebl/analysis/serial_position_report.json', json_tmp.name)
            with open(json_tmp.name, 'r', encoding='utf-8') as f:
                report = json.load(f)
            score += 10
            feedback_parts.append("[+10] Output file exists and is valid JSON.")
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Output file /home/ga/pebl/analysis/serial_position_report.json not found."}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Output file is not valid JSON: {e}"}
            
    finally:
        for tmp_path in [csv_tmp.name, json_tmp.name]:
            if os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except:
                    pass

    # Process agent data
    agent_participants = report.get('participants', [])
    agent_curve = report.get('group_serial_position_curve', [])
    
    agent_map = {}
    for p in agent_participants:
        pid = p.get('id') or p.get('participant_id')
        if pid:
            agent_map[str(pid)] = p

    # 3. Check Exclusion of sub-999
    sub999_agent = agent_map.get(CONTAMINATED_ID, {})
    is_excluded = sub999_agent.get('excluded') in (True, 'true', 1, 'yes')
    if not is_excluded and CONTAMINATED_ID not in agent_map:
        # Check if they just omitted it instead of explicit exclusion
        is_excluded = True
        
    if is_excluded:
        score += 20
        feedback_parts.append(f"[+20] {CONTAMINATED_ID} correctly excluded based on thresholds.")
    else:
        feedback_parts.append(f"[0] {CONTAMINATED_ID} not excluded despite matching exclusion criteria.")

    # 4. Check Valid Participants Count
    agent_valid_count = sum(1 for p in agent_map.values() if p.get('excluded') not in (True, 'true', 1, 'yes') and p.get('id') != CONTAMINATED_ID)
    if agent_valid_count == num_valid_gt:
        score += 15
        feedback_parts.append(f"[+15] Exactly {num_valid_gt} valid participants found.")
    else:
        feedback_parts.append(f"[0] Expected {num_valid_gt} valid participants, got {agent_valid_count}.")

    # 5. Check Individual Scores Accuracy
    correct_scores = 0
    total_scores_checked = 0
    
    for pid, gt_data in gt_scores.items():
        if gt_data['excluded']:
            continue
            
        agent_p = agent_map.get(pid, {})
        if agent_p.get('excluded'):
            continue # Already handled in count
            
        total_scores_checked += 1
        
        # Get metrics with fallbacks
        a_primacy = agent_p.get('primacy_score')
        a_middle = agent_p.get('middle_score')
        a_recency = agent_p.get('recency_score')
        a_overall = agent_p.get('overall_recall')
        
        if all(x is not None for x in [a_primacy, a_middle, a_recency, a_overall]):
            try:
                if (abs(float(a_primacy) - gt_data['primacy_score']) <= TOLERANCE and
                    abs(float(a_middle) - gt_data['middle_score']) <= TOLERANCE and
                    abs(float(a_recency) - gt_data['recency_score']) <= TOLERANCE and
                    abs(float(a_overall) - gt_data['overall_recall']) <= TOLERANCE):
                    correct_scores += 1
            except (ValueError, TypeError):
                pass
                
    if total_scores_checked > 0:
        ratio = correct_scores / total_scores_checked
        pts = int(30 * ratio)
        score += pts
        if pts == 30:
            feedback_parts.append("[+30] Individual participant scores computed perfectly.")
        else:
            feedback_parts.append(f"[+{pts}] Individual participant scores correct for {correct_scores}/{total_scores_checked}.")
    else:
        feedback_parts.append("[0] No valid participant scores to evaluate.")

    # 6. Check Group Serial Position Curve
    if isinstance(agent_curve, list) and len(agent_curve) == 15:
        curve_correct = 0
        for i in range(15):
            try:
                if abs(float(agent_curve[i]) - gt_curve[i]) <= TOLERANCE:
                    curve_correct += 1
            except (ValueError, TypeError):
                pass
                
        if curve_correct == 15:
            score += 25
            feedback_parts.append("[+25] Group Serial Position Curve matches ground truth perfectly.")
        else:
            pts = int(25 * (curve_correct / 15.0))
            score += pts
            feedback_parts.append(f"[+{pts}] Group Serial Position Curve matches at {curve_correct}/15 positions.")
    else:
        feedback_parts.append(f"[0] 'group_serial_position_curve' is missing or not a list of 15 values.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }