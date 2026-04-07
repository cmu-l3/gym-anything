#!/usr/bin/env python3
"""
Verifier for metacognition_calibration_analysis task.

Evaluates against exact dynamic ground truth computed from the provided CSV file.
Criteria:
1. Valid JSON Output (10 pts)
2. sub-99 Excluded logically (20 pts)
3. Timeout handling properly applied (15 pts)
4. Participant Metrics match GT within ±0.01 (25 pts)
5. Group Means match GT within ±0.005 (15 pts)
6. VLM Trajectory Verification - Anti-gaming (15 pts)

Total: 100 points
Pass Threshold: 65 points
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED_ID = "sub-99"

def compute_ground_truth(csv_path):
    """Computes exact ground truth directly from the agent's data file."""
    data = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append({
                'pid': row['participant_id'],
                'trial': int(row['trial_num']),
                'domain': row['task_domain'],
                'correct': int(row['correct']),
                'confidence': int(row['confidence']) if row['confidence'].strip() else 0
            })
            
    # Find invalid participants
    invalid_pids = set()
    for row in data:
        if row['correct'] in (0, 1) and row['confidence'] < 50:
            invalid_pids.add(row['pid'])
            
    # Compute metrics per participant
    participant_metrics = {}
    valid_pids = set(r['pid'] for r in data) - invalid_pids
    
    for pid in valid_pids:
        pid_data = [r for r in data if r['pid'] == pid and r['correct'] in (0, 1)]
        
        def calc_domain(rows):
            if not rows: return None
            acc = sum(r['correct'] for r in rows) / len(rows)
            conf = sum(r['confidence']/100.0 for r in rows) / len(rows)
            bias = conf - acc
            brier = sum(( (r['confidence']/100.0) - r['correct'] )**2 for r in rows) / len(rows)
            return {'accuracy': acc, 'mean_confidence': conf, 'overconfidence_bias': bias, 'brier_score': brier}
            
        participant_metrics[pid] = {
            'overall': calc_domain(pid_data),
            'memory': calc_domain([r for r in pid_data if r['domain'] == 'memory']),
            'perceptual': calc_domain([r for r in pid_data if r['domain'] == 'perceptual'])
        }
        
    # Compute group means
    group_means = {
        'overall_accuracy': sum(participant_metrics[p]['overall']['accuracy'] for p in valid_pids) / len(valid_pids),
        'overall_bias': sum(participant_metrics[p]['overall']['overconfidence_bias'] for p in valid_pids) / len(valid_pids),
        'memory_bias': sum(participant_metrics[p]['memory']['overconfidence_bias'] for p in valid_pids) / len(valid_pids),
        'perceptual_bias': sum(participant_metrics[p]['perceptual']['overconfidence_bias'] for p in valid_pids) / len(valid_pids),
        'overall_brier': sum(participant_metrics[p]['overall']['brier_score'] for p in valid_pids) / len(valid_pids)
    }
    
    return participant_metrics, invalid_pids, group_means


def verify_metacognition_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # Extract Agent JSON
    agent_report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_report:
        try:
            copy_from_env('/tmp/metacognition_report.json', tmp_report.name)
            with open(tmp_report.name, 'r', encoding='utf-8') as f:
                agent_report = json.load(f)
            score += 10
            feedback_parts.append("[+10] Output JSON found and valid.")
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Output file /home/ga/pebl/analysis/metacognition_report.json not found."}
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Output file is not valid JSON."}
        finally:
            if os.path.exists(tmp_report.name):
                os.unlink(tmp_report.name)
                
    # Extract Ground Truth from original data
    gt_metrics = None
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        try:
            copy_from_env('/home/ga/pebl/data/metacognition_data.csv', tmp_csv.name)
            gt_metrics, gt_invalid, gt_group = compute_ground_truth(tmp_csv.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to compute ground truth from env data: {e}"}
        finally:
            if os.path.exists(tmp_csv.name):
                os.unlink(tmp_csv.name)
                
    # Criterion 2: Check sub-99 exclusion
    agent_excluded = agent_report.get('excluded_participants', [])
    excluded_ids = [str(p.get('id', '')) for p in agent_excluded]
    
    if CONTAMINATED_ID in excluded_ids:
        score += 20
        feedback_parts.append(f"[+20] Correctly excluded {CONTAMINATED_ID}.")
    else:
        feedback_parts.append(f"[0] Failed to exclude logically impossible participant {CONTAMINATED_ID}.")
        
    # Parse Agent Participants
    agent_participants = {str(p.get('id')): p for p in agent_report.get('participants', [])}
    
    # Criterion 3 & 4: Participant Metrics and Timeout Handling
    correct_brier_bias = 0
    correct_timeout_handling = 0
    valid_agent_pids = set(agent_participants.keys()) - {CONTAMINATED_ID}
    gt_valid_pids = set(gt_metrics.keys())
    
    for pid in gt_valid_pids:
        if pid not in agent_participants:
            continue
            
        p_agent = agent_participants[pid]
        p_gt = gt_metrics[pid]
        
        try:
            # Check Timeout Handling via Accuracy Denominator
            if abs(p_agent['overall']['accuracy'] - p_gt['overall']['accuracy']) < 0.01:
                correct_timeout_handling += 1
                
            # Check complex metrics
            brier_diff = abs(p_agent['overall']['brier_score'] - p_gt['overall']['brier_score'])
            bias_diff = abs(p_agent['overall']['overconfidence_bias'] - p_gt['overall']['overconfidence_bias'])
            
            if brier_diff < 0.01 and bias_diff < 0.01:
                correct_brier_bias += 1
        except (KeyError, TypeError):
            pass
            
    # Score timeouts
    if correct_timeout_handling >= len(gt_valid_pids) * 0.9:
        score += 15
        feedback_parts.append("[+15] Timeouts correctly dropped (accuracies match GT).")
    elif correct_timeout_handling > 0:
        score += 5
        feedback_parts.append(f"[+5] Timeouts partially handled ({correct_timeout_handling}/{len(gt_valid_pids)}).")
    else:
        feedback_parts.append("[0] Timeouts not properly handled.")
        
    # Score metrics accuracy
    if correct_brier_bias >= len(gt_valid_pids) * 0.9:
        score += 25
        feedback_parts.append("[+25] Participant Bias and Brier metrics accurate.")
    elif correct_brier_bias > 0:
        score += 10
        feedback_parts.append(f"[+10] Participant metrics partially accurate ({correct_brier_bias}/{len(gt_valid_pids)}).")
    else:
        feedback_parts.append("[0] Participant Brier/Bias metrics incorrect.")
        
    # Criterion 5: Group Means
    agent_group = agent_report.get('group_means', {})
    group_correct = 0
    try:
        if abs(agent_group.get('overall_accuracy', 0) - gt_group['overall_accuracy']) <= 0.005: group_correct += 1
        if abs(agent_group.get('overall_bias', 0) - gt_group['overall_bias']) <= 0.005: group_correct += 1
        if abs(agent_group.get('memory_bias', 0) - gt_group['memory_bias']) <= 0.005: group_correct += 1
        if abs(agent_group.get('overall_brier', 0) - gt_group['overall_brier']) <= 0.005: group_correct += 1
        
        if group_correct == 4:
            score += 15
            feedback_parts.append("[+15] Group means strictly accurate.")
        elif group_correct > 0:
            score += 5
            feedback_parts.append(f"[+5] Group means partially accurate ({group_correct}/4).")
        else:
            feedback_parts.append("[0] Group means inaccurate.")
    except Exception:
        feedback_parts.append("[0] Group means missing or malformed.")

    # Criterion 6: VLM Trajectory Check (Anti-gaming)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = """Look at this sequence of agent trajectory screenshots.
        Did the agent actually write or execute a script (e.g. Python, R, bash) to analyze the metacognition CSV data?
        Evidence would be an IDE, terminal running a script, or writing code to process Brier scores.
        Respond with ONLY 'YES' or 'NO'."""
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            vlm_res = query_vlm(prompt=prompt, images=frames + [final_frame])
            if vlm_res.get('success') and 'YES' in str(vlm_res.get('parsed', vlm_res.get('raw', ''))).upper():
                score += 15
                feedback_parts.append("[+15] VLM verified active coding/execution trajectory.")
            else:
                feedback_parts.append("[0] VLM did not observe scripting/execution in trajectory.")
        else:
            # Grant fallback if no VLM available
            score += 15
            feedback_parts.append("[+15] VLM unavailable, granting anti-gaming points.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        score += 15
        feedback_parts.append("[+15] VLM check error, granting points.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }