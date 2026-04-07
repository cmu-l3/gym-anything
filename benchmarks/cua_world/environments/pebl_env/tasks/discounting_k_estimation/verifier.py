#!/usr/bin/env python3
"""
Verifier for discounting_k_estimation task.

Scoring System (100 points total):
1. Output file exists and is valid JSON (10 pts)
2. Corrupted participant sub-99999 correctly excluded (20 pts)
3. All 15 valid participants present (10 pts)
4. Individual k values within ±1.0 ln-unit for >=12 participants (30 pts)
5. Individual k values tighter tolerance (±0.5 ln-unit) for >=8 participants (10 pts bonus)
6. Group median ln_k within ±0.5 of ground truth (15 pts)
7. ln_k is mathematically consistent with k for all reported values (5 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_discounting_k_estimation(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Load Ground Truth
    # ---------------------------------------------------------
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_gt:
        tmp_gt_path = tmp_gt.name

    try:
        copy_from_env('/tmp/.discounting_gt.json', tmp_gt_path)
        with open(tmp_gt_path, 'r', encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load ground truth: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load ground truth (Environment Error)"}
    finally:
        if os.path.exists(tmp_gt_path):
            os.unlink(tmp_gt_path)

    # ---------------------------------------------------------
    # 2. Load Agent's Output JSON
    # ---------------------------------------------------------
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_out:
        tmp_out_path = tmp_out.name

    try:
        copy_from_env('/home/ga/pebl/analysis/discounting_report.json', tmp_out_path)
        with open(tmp_out_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output file exists and is valid JSON")
    except FileNotFoundError:
        feedback_parts.append("[0] Output file /home/ga/pebl/analysis/discounting_report.json not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f"[0] Output file is not valid JSON: {e}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(tmp_out_path):
            os.unlink(tmp_out_path)

    # ---------------------------------------------------------
    # 3. Analyze Participants List
    # ---------------------------------------------------------
    participants_list = report.get('participants', [])
    if not isinstance(participants_list, list):
        feedback_parts.append("[0] 'participants' key is missing or not a list")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(entry):
        return entry.get('excluded') in (True, 'true', 'Yes', 1)

    # Check sub-99999
    s99_entry = part_map.get('sub-99999')
    if s99_entry and is_excluded(s99_entry):
        score += 20
        feedback_parts.append("[+20] sub-99999 correctly marked as excluded")
    elif 'sub-99999' not in part_map and 'sub-99999' in str(report.get('excluded', [])):
        score += 20
        feedback_parts.append("[+20] sub-99999 correctly excluded")
    else:
        feedback_parts.append("[0] sub-99999 not correctly excluded (must be marked excluded or removed)")

    # Check presence of valid participants
    valid_pids = [p for p in gt_data.keys() if p.startswith('sub-')]
    present_valid = [p for p in valid_pids if p in part_map and not is_excluded(part_map[p])]
    
    if len(present_valid) == 15:
        score += 10
        feedback_parts.append("[+10] All 15 valid participants are present")
    else:
        feedback_parts.append(f"[0] Only {len(present_valid)}/15 valid participants present")

    # ---------------------------------------------------------
    # 4. Check Individual k Estimates
    # ---------------------------------------------------------
    correct_loose = 0
    correct_tight = 0
    consistent_math = True

    for pid in present_valid:
        entry = part_map[pid]
        gt_k = gt_data[pid]['k']
        gt_ln_k = gt_data[pid]['ln_k']
        
        reported_k = entry.get('k') or entry.get('k_value')
        reported_ln_k = entry.get('ln_k')

        try:
            if reported_k is not None:
                reported_k = float(reported_k)
                diff_ln = abs(math.log(reported_k) - gt_ln_k)
                
                if diff_ln <= 1.0:
                    correct_loose += 1
                if diff_ln <= 0.5:
                    correct_tight += 1
                
                # Check math consistency if ln_k is reported
                if reported_ln_k is not None:
                    calc_ln_k = math.log(reported_k)
                    if abs(calc_ln_k - float(reported_ln_k)) > 0.05:
                        consistent_math = False
        except (ValueError, TypeError):
            pass

    if correct_loose >= 12:
        score += 30
        feedback_parts.append(f"[+30] k values accurate (±1.0 ln-unit) for {correct_loose}/15 participants")
    elif correct_loose >= 6:
        score += 15
        feedback_parts.append(f"[+15] k values accurate for {correct_loose}/15 participants (partial)")
    else:
        feedback_parts.append(f"[0] k values accurate for only {correct_loose}/15 participants")

    if correct_tight >= 8:
        score += 10
        feedback_parts.append(f"[+10] k values highly accurate (±0.5 ln-unit) for {correct_tight}/15 participants")

    if consistent_math and len(present_valid) > 0:
        score += 5
        feedback_parts.append("[+5] ln_k values mathematically consistent with reported k values")

    # ---------------------------------------------------------
    # 5. Check Group Median
    # ---------------------------------------------------------
    reported_median_ln_k = report.get('group_median_ln_k')
    if reported_median_ln_k is None and report.get('group_median_k'):
        try:
            reported_median_ln_k = math.log(float(report.get('group_median_k')))
        except:
            pass
            
    gt_median_ln_k = gt_data.get('group_median_ln_k')
    
    if reported_median_ln_k is not None and gt_median_ln_k is not None:
        try:
            if abs(float(reported_median_ln_k) - gt_median_ln_k) <= 0.5:
                score += 15
                feedback_parts.append(f"[+15] Group median ln_k accurate (within ±0.5 of {gt_median_ln_k:.2f})")
            else:
                feedback_parts.append(f"[0] Group median ln_k inaccurate (reported {reported_median_ln_k}, expected ~{gt_median_ln_k:.2f})")
        except (ValueError, TypeError):
            feedback_parts.append("[0] Group median ln_k is not a valid number")
    else:
        feedback_parts.append("[0] Group median ln_k missing from report")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }