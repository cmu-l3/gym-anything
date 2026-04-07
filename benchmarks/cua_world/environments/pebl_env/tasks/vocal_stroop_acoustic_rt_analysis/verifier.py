#!/usr/bin/env python3
"""
Verifier for vocal_stroop_acoustic_rt_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON (10 pts)
  2. Corrupted participant p06 is correctly excluded (20 pts)
  3. Participant means (congruent/incongruent) within ±15ms of GT (40 pts)
  4. Group mean Stroop effect correct based on GT (30 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAMINATED_PARTICIPANT = 'p06'
VALID_PARTICIPANTS = ['p01', 'p02', 'p03', 'p04', 'p05']
TOLERANCE_MS = 15.0
PASS_THRESHOLD = 60

def verify_vocal_stroop(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # --- Criterion 1: Load Output JSON ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_report = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/vocal_rt_report.json', tmp_report)
        with open(tmp_report, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Output file ~/pebl/analysis/vocal_rt_report.json not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Output file is not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(tmp_report):
            os.unlink(tmp_report)

    # --- Load Ground Truth JSON ---
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_gt = tmp.name

    try:
        copy_from_env('/var/lib/app/ground_truth/vocal_rts.json', tmp_gt)
        with open(tmp_gt, encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f"Verifier error loading ground truth: {e}"}
    finally:
        if os.path.exists(tmp_gt):
            os.unlink(tmp_gt)

    # Parse participant list
    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id')
        if pid:
            part_map[str(pid)] = entry

    # --- Criterion 2: Exclude p06 ---
    p06_entry = part_map.get(CONTAMINATED_PARTICIPANT)
    if p06_entry and p06_entry.get('excluded') in (True, 'true', 1, 'yes'):
        score += 20
        feedback_parts.append(f'[+20] Participant {CONTAMINATED_PARTICIPANT} correctly excluded.')
    else:
        feedback_parts.append(f'[0] Participant {CONTAMINATED_PARTICIPANT} not excluded. Broken audio was not handled correctly.')

    # --- Criterion 3: Participant Means ---
    correct_means = 0
    total_means_to_check = len(VALID_PARTICIPANTS) * 2
    
    gt_stroop_effects = []

    for pid in VALID_PARTICIPANTS:
        gt_cong = gt_data[pid]['congruent']
        gt_incong = gt_data[pid]['incongruent']
        gt_stroop_effects.append(gt_incong - gt_cong)
        
        entry = part_map.get(pid)
        if not entry:
            continue
            
        cong_ms = entry.get('mean_rt_congruent_ms')
        incong_ms = entry.get('mean_rt_incongruent_ms')

        if cong_ms is not None:
            try:
                if abs(float(cong_ms) - gt_cong) <= TOLERANCE_MS:
                    correct_means += 1
            except (ValueError, TypeError):
                pass
                
        if incong_ms is not None:
            try:
                if abs(float(incong_ms) - gt_incong) <= TOLERANCE_MS:
                    correct_means += 1
            except (ValueError, TypeError):
                pass

    points_per_mean = 40.0 / total_means_to_check
    earned_mean_points = int(correct_means * points_per_mean)
    score += earned_mean_points
    feedback_parts.append(f'[+{earned_mean_points}] {correct_means}/{total_means_to_check} participant means correct (within ±{TOLERANCE_MS}ms).')

    # --- Criterion 4: Group Mean Stroop Effect ---
    gt_group_stroop = sum(gt_stroop_effects) / len(gt_stroop_effects)
    reported_group_stroop = report.get('group_mean_stroop_effect_ms')
    
    if reported_group_stroop is not None:
        try:
            if abs(float(reported_group_stroop) - gt_group_stroop) <= TOLERANCE_MS:
                score += 30
                feedback_parts.append('[+30] Group mean Stroop effect correct.')
            else:
                feedback_parts.append(f'[0] Group mean Stroop effect {reported_group_stroop} is incorrect (expected ~{gt_group_stroop:.1f}).')
        except (ValueError, TypeError):
            feedback_parts.append('[0] group_mean_stroop_effect_ms is not a number.')
    else:
        feedback_parts.append('[0] group_mean_stroop_effect_ms missing.')

    # Final Evaluation
    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }