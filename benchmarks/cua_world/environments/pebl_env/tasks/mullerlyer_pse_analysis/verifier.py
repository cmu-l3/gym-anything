#!/usr/bin/env python3
"""
Verifier for mullerlyer_pse_analysis task.

Verifies the agent's psychometric curve fitting and data cleaning.
Scoring System (100 points total):
  1. Output file exists and is valid JSON (10 pts)
  2. P99 correctly excluded with reason (20 pts)
  3. PSE estimates within ±5px for ≥11 of 15 valid participants (30 pts)
  4. Illusion magnitudes within ±5px for ≥11 of 15 valid participants (20 pts)
  5. Group mean illusion within ±3px of ground truth (20 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Tolerances
PSE_TOLERANCE = 5.0
ILLUSION_TOLERANCE = 5.0
GROUP_MEAN_TOLERANCE = 3.0
MIN_CORRECT_PARTICIPANTS = 11

def verify_mullerlyer_pse_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read Ground Truth
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_gt:
        gt_path = tmp_gt.name
    try:
        # Use sudo/root copy if necessary by the framework, but copy_from_env usually handles absolute paths
        copy_from_env('/var/lib/pebl/ground_truth/mullerlyer_gt.json', gt_path)
        with open(gt_path, 'r', encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load ground truth: {e}")
        return {"passed": False, "score": 0, "feedback": "Verifier internal error: Missing ground truth."}
    finally:
        if os.path.exists(gt_path):
            os.unlink(gt_path)

    # 2. Read Agent Report
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_rep:
        rep_path = tmp_rep.name
    try:
        copy_from_env('/home/ga/pebl/analysis/mullerlyer_report.json', rep_path)
        with open(rep_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output file exists and is valid JSON.")
    except FileNotFoundError:
        feedback_parts.append("[0] Output file /home/ga/pebl/analysis/mullerlyer_report.json not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    except json.JSONDecodeError:
        feedback_parts.append("[0] Output file is not valid JSON.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    finally:
        if os.path.exists(rep_path):
            os.unlink(rep_path)

    # Parse participant data
    participants_list = report.get('participants', [])
    if not isinstance(participants_list, list):
        feedback_parts.append("[0] 'participants' key is missing or not a list.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    # Criterion 2: Check P99 Exclusion
    p99_entry = part_map.get("P99")
    if p99_entry and str(p99_entry.get("excluded")).lower() in ["true", "1", "yes"]:
        score += 20
        feedback_parts.append("[+20] P99 correctly marked as excluded.")
    else:
        feedback_parts.append("[0] P99 not correctly excluded in the report.")

    # Criterion 3 & 4: Evaluate PSEs and Illusion Magnitudes
    correct_pses = 0
    correct_illusions = 0
    valid_ppts = [f"P{i:02d}" for i in range(1, 16)]

    for pid in valid_ppts:
        gt = gt_data.get(pid)
        entry = part_map.get(pid)
        if not gt or not entry or str(entry.get("excluded")).lower() in ["true", "1", "yes"]:
            continue

        # Extract values (allowing slight variations in key names)
        pse_in = entry.get('pse_fins_in') or entry.get('pse_in')
        pse_out = entry.get('pse_fins_out') or entry.get('pse_out')
        illusion = entry.get('illusion_magnitude') or entry.get('illusion')

        try:
            # Check PSEs
            if pse_in is not None and pse_out is not None:
                if (abs(float(pse_in) - gt["pse_fins_in"]) <= PSE_TOLERANCE and 
                    abs(float(pse_out) - gt["pse_fins_out"]) <= PSE_TOLERANCE):
                    correct_pses += 1
            
            # Check Illusion
            if illusion is not None:
                if abs(float(illusion) - gt["illusion_magnitude"]) <= ILLUSION_TOLERANCE:
                    correct_illusions += 1
                # Accept if they derived it manually but didn't put it in the dict directly, 
                # but instruction says to include it. If missing, they don't get the point.
        except (ValueError, TypeError):
            pass

    if correct_pses >= MIN_CORRECT_PARTICIPANTS:
        score += 30
        feedback_parts.append(f"[+30] PSE estimates within ±{PSE_TOLERANCE}px for {correct_pses}/15 participants.")
    else:
        feedback_parts.append(f"[0] PSE estimates accurate for only {correct_pses}/15 participants (requires {MIN_CORRECT_PARTICIPANTS}).")

    if correct_illusions >= MIN_CORRECT_PARTICIPANTS:
        score += 20
        feedback_parts.append(f"[+20] Illusion magnitudes within ±{ILLUSION_TOLERANCE}px for {correct_illusions}/15 participants.")
    else:
        feedback_parts.append(f"[0] Illusion magnitudes accurate for only {correct_illusions}/15 participants.")

    # Criterion 5: Group Mean Illusion
    gt_mean_illusion = sum(gt["illusion_magnitude"] for gt in gt_data.values()) / 15.0
    reported_mean_illusion = report.get('group_mean_illusion_magnitude') or report.get('group_mean_illusion')

    if reported_mean_illusion is not None:
        try:
            if abs(float(reported_mean_illusion) - gt_mean_illusion) <= GROUP_MEAN_TOLERANCE:
                score += 20
                feedback_parts.append(f"[+20] Group mean illusion correct (expected ~{gt_mean_illusion:.2f}, got {reported_mean_illusion}).")
            else:
                feedback_parts.append(f"[0] Group mean illusion incorrect (expected ~{gt_mean_illusion:.2f}, got {reported_mean_illusion}).")
        except (ValueError, TypeError):
            feedback_parts.append("[0] Group mean illusion is not a valid number.")
    else:
        feedback_parts.append("[0] 'group_mean_illusion_magnitude' missing from report.")

    # Determine final pass/fail
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }