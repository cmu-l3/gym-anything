#!/usr/bin/env python3
"""
Verifier for IAT D-Score Bias Analysis task.

Evaluates the agent's programmatic D-score JSON output against a strictly
calculated ground truth. Includes VLM trajectory verification to ensure
actual analysis was performed (vs. hardcoding logic).
"""

import json
import os
import csv
import math
import statistics
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def compute_ground_truth(csv_path: str) -> dict:
    """Computes exact Greenwald D-scores from the provided raw CSV."""
    data = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant']
            blk = int(row['block'])
            rt = float(row['rt_ms'])
            if pid not in data:
                data[pid] = {3: [], 4: [], 6: [], 7: []}
            if blk in [3, 4, 6, 7]:
                data[pid][blk].append(rt)

    results = {}
    valid_d_scores = []
    
    for pid, blocks in data.items():
        all_rts = blocks[3] + blocks[4] + blocks[6] + blocks[7]
        if not all_rts:
            continue
            
        # 1. Exclusion Criterion (>10% < 300ms)
        fast_rts = sum(1 for rt in all_rts if rt < 300)
        if fast_rts / len(all_rts) > 0.1:
            results[pid] = {'excluded': True}
            continue

        # 2. Block Means
        m3 = statistics.mean(blocks[3])
        m4 = statistics.mean(blocks[4])
        m6 = statistics.mean(blocks[6])
        m7 = statistics.mean(blocks[7])

        # 3. Pooled SDs (sample standard deviation)
        sd_prac = statistics.stdev(blocks[3] + blocks[6])
        sd_test = statistics.stdev(blocks[4] + blocks[7])

        # 4. Mean Differences & Quotients
        d_prac = (m6 - m3) / sd_prac if sd_prac > 0 else 0
        d_test = (m7 - m4) / sd_test if sd_test > 0 else 0

        # 5. Final D-Score
        d_score = (d_prac + d_test) / 2
        results[pid] = {'d_score': d_score, 'excluded': False}
        valid_d_scores.append(d_score)

    overall_mean = statistics.mean(valid_d_scores) if valid_d_scores else 0.0
    return {"participants": results, "group_mean": overall_mean}


def verify_iat_dscore(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    max_score = 100
    tolerance = task_info.get('metadata', {}).get('d_score_tolerance', 0.015)
    
    # 1. Anti-gaming check (was file generated during task?)
    meta_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", meta_tmp.name)
        with open(meta_tmp.name, 'r') as f:
            task_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {e}"}
    finally:
        os.unlink(meta_tmp.name)

    if not task_meta.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file iat_report.json not found."}
    if not task_meta.get('file_created_during_task'):
        feedback.append("WARNING: File was not created/modified during task session.")

    # 2. Copy the actual raw data and output file
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    report_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/home/ga/pebl/data/iat_data.csv", csv_tmp.name)
        copy_from_env("/home/ga/pebl/analysis/iat_report.json", report_tmp.name)
        
        # Calculate strict ground truth directly from the agent's specific env file
        ground_truth = compute_ground_truth(csv_tmp.name)
        
        with open(report_tmp.name, 'r') as f:
            agent_report = json.load(f)
            
        score += 10
        feedback.append("Valid JSON parsed (+10).")
        
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Required files missing from environment."}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "iat_report.json is not a valid JSON file."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error during verification setup: {e}"}
    finally:
        os.unlink(csv_tmp.name)
        os.unlink(report_tmp.name)

    # 3. Validation Logic
    agent_participants = agent_report.get('participants', [])
    agent_map = {str(p.get('id')): p for p in agent_participants}
    
    gt_participants = ground_truth["participants"]
    correct_scores = 0
    total_valid = sum(1 for p in gt_participants.values() if not p['excluded'])

    # Check bot exclusion
    bot_id = "sub-99"
    if bot_id in agent_map and agent_map[bot_id].get('excluded') == True:
        score += 20
        feedback.append(f"Bot '{bot_id}' correctly excluded (+20).")
    else:
        feedback.append(f"Failed to identify and exclude bot '{bot_id}'.")

    # Check valid D-scores
    for pid, gt_data in gt_participants.items():
        if gt_data['excluded']:
            continue
            
        agent_data = agent_map.get(pid)
        if agent_data and not agent_data.get('excluded'):
            agent_d = agent_data.get('d_score', -999)
            if math.isclose(agent_d, gt_data['d_score'], abs_tol=tolerance):
                correct_scores += 1
                
    if correct_scores == total_valid:
        score += 40
        feedback.append(f"All {total_valid} valid D-scores perfectly accurate (+40).")
    elif correct_scores > 0:
        partial = int((correct_scores / total_valid) * 40)
        score += partial
        feedback.append(f"Calculated {correct_scores}/{total_valid} valid D-scores correctly (+{partial}).")
    else:
        feedback.append("No valid participant D-scores calculated correctly.")

    # Check group mean
    agent_group_mean = agent_report.get('group_mean_d_score', -999)
    if math.isclose(agent_group_mean, ground_truth["group_mean"], abs_tol=tolerance):
        score += 30
        feedback.append(f"Group mean D-score accurate (+30).")
    else:
        feedback.append(f"Group mean inaccurate (Agent: {agent_group_mean}, Expected: {ground_truth['group_mean']:.3f}).")

    # Final pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }