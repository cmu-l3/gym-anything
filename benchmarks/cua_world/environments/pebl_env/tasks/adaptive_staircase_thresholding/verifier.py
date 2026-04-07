#!/usr/bin/env python3
"""
Verifier for adaptive_staircase_thresholding task.

Uses `copy_from_env` to download BOTH the generated data CSV and the agent's report.
It calculates the exact ground truth dynamically from the CSV data to compare against the agent's output.

Scoring (100 points):
1. Output file exists and was created during the task (10 pts)
2. Valid JSON format matching schema (10 pts)
3. Exclusion 1: Impossibly fast RT < 150ms correctly flagged (15 pts)
4. Exclusion 2: Failure to converge < 6 reversals correctly flagged (15 pts)
5. Reversal extraction & threshold arithmetic accuracy (35 pts)
6. Group mean threshold accuracy (15 pts)
7. VLM: Validates trajectory for evidence of scripting/algorithmic work (Anti-gaming)
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Verification Prompt ---
VLM_PROMPT = """You are auditing a computer agent's trajectory for an algorithmic data analysis task.
The agent was asked to calculate adaptive staircase thresholds from a CSV file.
Look at these sampled screenshots from the agent's screen during the task.

Does the agent use a scripting language (like Python, R, or Bash), a spreadsheet software, or a data analysis tool to parse the CSV and compute the results?
We are looking for evidence of REAL WORK (e.g., writing code, running a script in the terminal, looking at data in an editor) rather than just copy-pasting a pre-made JSON file.

Respond ONLY with a JSON object:
{
    "evidence_of_scripting": true/false,
    "tools_used": ["list", "of", "tools"],
    "reasoning": "brief explanation"
}
"""

def compute_ground_truth(csv_path):
    """
    Computes the ground truth directly from the simulated CSV data.
    Ensures absolute alignment with the instructions given to the agent.
    """
    participants_data = {}
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            if pid not in participants_data:
                participants_data[pid] = {'contrasts': [], 'rts': []}
            participants_data[pid]['contrasts'].append(float(row['target_contrast']))
            participants_data[pid]['rts'].append(float(row['rt_ms']))
            
    results = {}
    valid_thresholds = []
    
    for pid, data in participants_data.items():
        contrasts = data['contrasts']
        rts = data['rts']
        
        # 5. Check Mean RT < 150ms
        mean_rt = sum(rts) / len(rts) if rts else 0
        if mean_rt < 150.0:
            results[pid] = {"excluded": True, "reason": "Mean RT < 150ms"}
            continue
            
        # 2. Compress the sequence
        comp = [contrasts[0]]
        for val in contrasts[1:]:
            if val != comp[-1]:
                comp.append(val)
                
        # 3. Identify reversals (local extrema)
        revs = []
        for i in range(1, len(comp)-1):
            if (comp[i] > comp[i-1] and comp[i] > comp[i+1]) or \
               (comp[i] < comp[i-1] and comp[i] < comp[i+1]):
                revs.append(comp[i])
                
        # 4. Check convergence (< 6 reversals)
        if len(revs) < 6:
            results[pid] = {"excluded": True, "reason": "Failed to converge (< 6 reversals)"}
            continue
            
        # 6 & 7. Discard first 2 (burn-in) and average
        valid_revs = revs[2:]
        threshold = sum(valid_revs) / len(valid_revs)
        
        results[pid] = {
            "excluded": False,
            "reversals_found": len(revs),
            "threshold": threshold
        }
        valid_thresholds.append(threshold)
        
    group_mean = sum(valid_thresholds) / len(valid_thresholds) if valid_thresholds else 0
    return results, group_mean


def verify_adaptive_staircase(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read task execution metadata
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_meta:
        meta_path = tmp_meta.name
    try:
        copy_from_env('/tmp/task_result.json', meta_path)
        with open(meta_path, 'r') as f:
            meta = json.load(f)
            
        if not meta.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Report file not found at expected path."}
        if not meta.get('file_created_during_task'):
            feedback_parts.append("[0] Warning: Output file existed before task start (possible gaming).")
        else:
            score += 10
            feedback_parts.append("[+10] File created during task.")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(meta_path): os.unlink(meta_path)

    # 2. Fetch the CSV to compute Ground Truth dynamically
    with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as tmp_csv:
        csv_path = tmp_csv.name
    try:
        copy_from_env('/home/ga/pebl/data/contrast_staircase_data.csv', csv_path)
        gt_results, gt_group_mean = compute_ground_truth(csv_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to fetch or parse CSV data: {e}"}
    finally:
        if os.path.exists(csv_path): os.unlink(csv_path)

    # 3. Read the Agent's Report
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_report:
        report_path = tmp_report.name
    try:
        copy_from_env('/home/ga/pebl/analysis/staircase_report.json', report_path)
        with open(report_path, 'r', encoding='utf-8') as f:
            agent_report = json.load(f)
        score += 10
        feedback_parts.append("[+10] JSON is valid.")
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Report JSON invalid: {e}"}
    finally:
        if os.path.exists(report_path): os.unlink(report_path)

    # Extract agent participants dict
    participants_list = agent_report.get('participants', [])
    agent_parts = {}
    for p in participants_list:
        pid = p.get('id') or p.get('participant_id')
        if pid:
            agent_parts[str(pid)] = p

    # Evaluate Specific Criteria
    
    # Check Exclusion 1: Fast RT (sub-99)
    sub99_agent = agent_parts.get('sub-99', {})
    if sub99_agent.get('excluded') in [True, 'true', 'yes', 1]:
        score += 15
        feedback_parts.append("[+15] sub-99 correctly excluded (Fast RT).")
    else:
        feedback_parts.append("[0] sub-99 not excluded (missed RT condition).")

    # Check Exclusion 2: Convergence (sub-04)
    sub04_agent = agent_parts.get('sub-04', {})
    if sub04_agent.get('excluded') in [True, 'true', 'yes', 1]:
        score += 15
        feedback_parts.append("[+15] sub-04 correctly excluded (Convergence failure).")
    else:
        feedback_parts.append("[0] sub-04 not excluded (missed convergence condition).")

    # Check Accuracy of valid participants
    correct_reversals = 0
    correct_thresholds = 0
    valid_count = 0
    
    for pid, gt_data in gt_results.items():
        if gt_data['excluded']:
            continue
            
        valid_count += 1
        agent_p = agent_parts.get(pid, {})
        
        # Check reversals
        if agent_p.get('reversals_found') == gt_data['reversals_found']:
            correct_reversals += 1
            
        # Check thresholds
        agent_thresh = agent_p.get('threshold_contrast')
        if agent_thresh is not None:
            try:
                if abs(float(agent_thresh) - gt_data['threshold']) <= 0.5:
                    correct_thresholds += 1
            except (ValueError, TypeError):
                pass

    if valid_count > 0:
        rev_accuracy = correct_reversals / valid_count
        thresh_accuracy = correct_thresholds / valid_count
        
        if rev_accuracy >= 0.8 and thresh_accuracy >= 0.8:
            score += 35
            feedback_parts.append(f"[+35] Reversal/Threshold calculation excellent ({correct_thresholds}/{valid_count} correct).")
        elif thresh_accuracy >= 0.5:
            score += 15
            feedback_parts.append(f"[+15] Reversal/Threshold calculation partial ({correct_thresholds}/{valid_count} correct).")
        else:
            feedback_parts.append(f"[0] Reversal/Threshold calculation poor ({correct_thresholds}/{valid_count} correct).")
            
    # Check Group Mean
    agent_group_mean = agent_report.get('group_mean_threshold')
    if agent_group_mean is not None:
        try:
            if abs(float(agent_group_mean) - gt_group_mean) <= 0.5:
                score += 15
                feedback_parts.append("[+15] Group mean threshold accurate.")
            else:
                feedback_parts.append(f"[0] Group mean inaccurate (expected ~{gt_group_mean:.1f}).")
        except:
            feedback_parts.append("[0] Group mean invalid format.")

    # VLM Trajectory Verification
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames = sample_trajectory_frames(trajectory, n=4)
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('evidence_of_scripting', False):
                feedback_parts.append("VLM confirms scripting/tool usage.")
            else:
                feedback_parts.append("VLM: No evidence of scripting seen (gaming warning).")
                # Penalty for gaming the JSON output without doing work
                score = min(score, 50) 
    except Exception as e:
        logger.warning(f"VLM Trajectory verification failed: {e}")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }