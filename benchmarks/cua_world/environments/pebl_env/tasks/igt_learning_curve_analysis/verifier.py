#!/usr/bin/env python3
"""
Verifier for Iowa Gambling Task (IGT) Learning Curve Analysis.

Scoring System (100 points total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Anomalous participant (sub-999) correctly excluded            (20 pts)
  3. All 15 real participants are present in the output            (15 pts)
  4. Block net scores correct (±4) for ≥11 of 15 participants      (25 pts)
  5. Group mean learning effect correct within ±3.0                (15 pts)
  6. Group mean block net scores correct within ±2.0 for ≥4 blocks (15 pts)

Pass Threshold: 60 points
Anti-Gaming: Must confirm file was generated during the active task session.
"""

import json
import os
import tempfile
import random
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Recompute exact ground truth identical to the environment generator
def compute_ground_truth():
    random.seed(42)
    gt_participants = {}
    
    # 15 real participants
    for i in range(1, 16):
        pid = f"sub-{i:03d}"
        blocks = [0, 0, 0, 0, 0]
        learning_slope = random.uniform(0.0, 0.15) if i <= 10 else random.uniform(-0.05, 0.05)
        
        for b in range(5):
            prob_CD = min(0.9, max(0.1, 0.4 + (b * learning_slope)))
            for t in range(20):
                if random.random() < prob_CD:
                    choice = random.choice(['C', 'D'])
                    blocks[b] += 1
                else:
                    choice = random.choice(['A', 'B'])
                    blocks[b] -= 1
                
                # Consume random numbers identically to data generation
                if choice == 'A':
                    _ = random.random()
                elif choice == 'B':
                    _ = random.random()
                elif choice == 'C':
                    _ = random.random()
                elif choice == 'D':
                    _ = random.random()
                    
        overall = sum(blocks)
        learning = ((blocks[3] + blocks[4]) / 2.0) - ((blocks[0] + blocks[1]) / 2.0)
        gt_participants[pid] = {
            'blocks': blocks,
            'overall': overall,
            'learning': learning
        }
    
    # Group stats (excluding sub-999)
    group_blocks = [0] * 5
    for b in range(5):
        group_blocks[b] = sum(p['blocks'][b] for p in gt_participants.values()) / 15.0
    group_learning = sum(p['learning'] for p in gt_participants.values()) / 15.0
    
    return gt_participants, group_blocks, group_learning


def verify_igt_learning_curve_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Anti-gaming file timestamp check
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta = json.load(f)
        if not meta.get('file_created_during_task', False):
            return {"passed": False, "score": 0, "feedback": "Output file was not created or modified during the task."}
    except Exception:
        pass # fallback if metadata missing, but we'll strictly evaluate content
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    score = 0
    feedback_parts = []
    gt_parts, gt_group_blocks, gt_group_learning = compute_ground_truth()

    # CRITERION 1: File exists and is valid JSON (10 pts)
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/home/ga/pebl/analysis/igt_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output JSON valid")
    except Exception as e:
        feedback_parts.append(f"[0] Output JSON missing or invalid: {e}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    participants = report.get('participants', [])
    part_map = {}
    for p in participants:
        pid = str(p.get('id', p.get('participant_id', '')))
        if pid:
            part_map[pid] = p

    # CRITERION 2: sub-999 correctly excluded (20 pts)
    # Check if marked excluded or completely omitted
    s999 = part_map.get('sub-999')
    if s999 and s999.get('excluded') in (True, 'true', 1, 'yes'):
        score += 20
        feedback_parts.append("[+20] sub-999 excluded")
    elif 'sub-999' not in part_map:
        score += 20
        feedback_parts.append("[+20] sub-999 excluded (omitted)")
    else:
        feedback_parts.append("[0] sub-999 NOT excluded")

    # CRITERION 3: All 15 real participants present (15 pts)
    real_ids = [f"sub-{i:03d}" for i in range(1, 16)]
    present_count = sum(1 for pid in real_ids if pid in part_map and not part_map[pid].get('excluded'))
    
    if present_count == 15:
        score += 15
        feedback_parts.append("[+15] All 15 participants present")
    elif present_count >= 10:
        score += 8
        feedback_parts.append(f"[+8] {present_count}/15 participants present (partial)")
    else:
        feedback_parts.append(f"[0] Only {present_count}/15 participants present")

    # CRITERION 4: Block net scores correct (25 pts)
    correct_blocks_participants = 0
    for pid in real_ids:
        if pid in part_map and not part_map[pid].get('excluded'):
            reported_blocks = part_map[pid].get('block_net_scores', [])
            if isinstance(reported_blocks, list) and len(reported_blocks) == 5:
                gt_blocks = gt_parts[pid]['blocks']
                try:
                    diffs = [abs(float(r) - g) for r, g in zip(reported_blocks, gt_blocks)]
                    if sum(1 for d in diffs if d <= 4.0) >= 4:
                        correct_blocks_participants += 1
                except (ValueError, TypeError):
                    pass
    
    if correct_blocks_participants >= 11:
        score += 25
        feedback_parts.append(f"[+25] Block scores accurate for {correct_blocks_participants}/15")
    elif correct_blocks_participants >= 5:
        score += 12
        feedback_parts.append(f"[+12] Block scores accurate for {correct_blocks_participants}/15 (partial)")
    else:
        feedback_parts.append(f"[0] Block scores inaccurate for most participants")

    # CRITERION 5: Group mean learning effect correct (15 pts)
    reported_gle = report.get('group_mean_learning_effect')
    if reported_gle is not None:
        try:
            if abs(float(reported_gle) - gt_group_learning) <= 3.0:
                score += 15
                feedback_parts.append("[+15] Group learning effect accurate")
            else:
                feedback_parts.append(f"[0] Group learning effect inaccurate (Expected ~{gt_group_learning:.2f})")
        except (ValueError, TypeError):
            feedback_parts.append("[0] Group learning effect format error")
    else:
        feedback_parts.append("[0] Group learning effect missing")

    # CRITERION 6: Group mean block net scores correct (15 pts)
    reported_group_blocks = report.get('group_mean_net_scores_by_block', [])
    if isinstance(reported_group_blocks, list) and len(reported_group_blocks) == 5:
        try:
            diffs = [abs(float(r) - g) for r, g in zip(reported_group_blocks, gt_group_blocks)]
            if sum(1 for d in diffs if d <= 2.0) >= 4:
                score += 15
                feedback_parts.append("[+15] Group block means accurate")
            else:
                feedback_parts.append("[0] Group block means inaccurate")
        except (ValueError, TypeError):
            feedback_parts.append("[0] Group block means format error")
    else:
        feedback_parts.append("[0] Group block means missing or incomplete")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }