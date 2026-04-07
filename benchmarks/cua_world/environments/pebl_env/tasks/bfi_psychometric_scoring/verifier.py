#!/usr/bin/env python3
"""
Verifier for BFI Psychometric Scoring and Quality Control task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON (10 pts)
  2. Identifies Speeders (median RT < 500ms) (15 pts)
  3. Identifies Straight-liners (response SD < 0.25) (15 pts)
  4. Applies Reverse Scoring correctly (math check against GT) (30 pts)
  5. Applies Non-Reverse Scoring correctly (10 pts)
  6. Group means calculated correctly across valid participants (20 pts)

Uses dynamically generated ground truth to strictly prevent gaming.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bfi_scoring(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Load Agent's Output
    agent_report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        agent_out_path = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/bfi_report.json', agent_out_path)
        with open(agent_out_path, encoding='utf-8') as f:
            agent_report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output file exists and is valid JSON")
    except FileNotFoundError:
        feedback_parts.append("[0] Output file ~/pebl/analysis/bfi_report.json not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f"[0] Output file is not valid JSON: {e}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(agent_out_path):
            os.unlink(agent_out_path)

    # 2. Load Hidden Ground Truth
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        gt_path = tmp.name

    try:
        copy_from_env('/tmp/hidden_bfi_ground_truth.json', gt_path)
        with open(gt_path, encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(gt_path):
            os.unlink(gt_path)

    gt_participants = gt_data.get("participants", {})
    gt_group_means = gt_data.get("group_means", {})

    # Map agent's participant list for easy lookup
    agent_participants = {}
    for p in agent_report.get("participants", []):
        if "id" in p:
            agent_participants[p["id"]] = p

    # --- CRITERIA 2 & 3: Exclusions (Speeders & Straightliners) ---
    correctly_excluded_speeders = 0
    correctly_excluded_sl = 0
    target_speeders = 0
    target_sl = 0

    for pid, gt_p in gt_participants.items():
        if gt_p.get("excluded"):
            reason = gt_p.get("reason", "")
            is_speeder = "speeding" in reason
            is_sl = "straight-lining" in reason
            
            if is_speeder: target_speeders += 1
            if is_sl: target_sl += 1

            agent_p = agent_participants.get(pid, {})
            # Accept either explicit boolean 'excluded: true' or omission of traits as exclusion
            is_agent_excluded = agent_p.get("excluded") is True or "traits" not in agent_p

            if is_agent_excluded:
                if is_speeder: correctly_excluded_speeders += 1
                if is_sl: correctly_excluded_sl += 1

    if target_speeders > 0 and correctly_excluded_speeders == target_speeders:
        score += 15
        feedback_parts.append("[+15] Speeders correctly excluded")
    else:
        feedback_parts.append(f"[0] Speeders missed (found {correctly_excluded_speeders}/{target_speeders})")

    if target_sl > 0 and correctly_excluded_sl == target_sl:
        score += 15
        feedback_parts.append("[+15] Straight-liners correctly excluded")
    else:
        feedback_parts.append(f"[0] Straight-liners missed (found {correctly_excluded_sl}/{target_sl})")

    # --- CRITERIA 4 & 5: Individual Math Checks (Reverse & Non-Reverse) ---
    math_correct_count = 0
    valid_target_count = sum(1 for p in gt_participants.values() if not p.get("excluded"))
    
    for pid, gt_p in gt_participants.items():
        if not gt_p.get("excluded"):
            agent_p = agent_participants.get(pid, {})
            agent_traits = agent_p.get("traits", {})
            gt_traits = gt_p.get("traits", {})
            
            # Check if all traits match within 0.05 tolerance
            matches = 0
            for trait, gt_val in gt_traits.items():
                agent_val = agent_traits.get(trait)
                if agent_val is not None:
                    try:
                        if abs(float(agent_val) - gt_val) <= 0.05:
                            matches += 1
                    except (ValueError, TypeError):
                        pass
                        
            if matches == 5:
                math_correct_count += 1

    if valid_target_count > 0:
        ratio = math_correct_count / valid_target_count
        if ratio >= 0.9:
            score += 40 # Covers both reverse (30) and non-reverse (10)
            feedback_parts.append(f"[+40] Trait scoring math correct for valid participants")
        elif ratio >= 0.5:
            score += 20
            feedback_parts.append(f"[+20] Trait scoring math partially correct ({math_correct_count}/{valid_target_count})")
        else:
            feedback_parts.append(f"[0] Trait scoring math incorrect ({math_correct_count}/{valid_target_count})")

    # --- CRITERION 6: Group Means ---
    agent_group_means = agent_report.get("group_means", {})
    group_matches = 0
    for trait, gt_val in gt_group_means.items():
        agent_val = agent_group_means.get(trait)
        if agent_val is not None:
            try:
                if abs(float(agent_val) - gt_val) <= 0.05:
                    group_matches += 1
            except (ValueError, TypeError):
                pass

    if group_matches == 5:
        score += 20
        feedback_parts.append("[+20] Group means calculated correctly")
    elif group_matches > 0:
        score += (group_matches * 4)
        feedback_parts.append(f"[+{group_matches * 4}] Group means partially correct ({group_matches}/5)")
    else:
        feedback_parts.append("[0] Group means incorrect or missing")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }