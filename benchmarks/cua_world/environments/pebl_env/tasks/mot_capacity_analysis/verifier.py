#!/usr/bin/env python3
"""
Verifier for MOT Capacity Analysis Task.

Criteria:
1. JSON output exists and is valid (10 pts)
2. capacity_plot.png generated (10 pts)
3. Outlier participant (MOT_99) excluded (20 pts)
4. Participant k_capacity mathematics correct (30 pts)
5. Group mean capacities correct and naturally exclude the outlier (30 pts)

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mot_capacity_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Load Ground Truth
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        try:
            copy_from_env('/tmp/mot_ground_truth.json', tmp.name)
            with open(tmp.name, 'r') as f:
                gt = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load Ground Truth: {e}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 2. Check JSON Output (10 pts)
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        try:
            copy_from_env('/home/ga/pebl/analysis/mot_capacity_report.json', tmp.name)
            with open(tmp.name, 'r') as f:
                report = json.load(f)
            score += 10
            feedback.append("[+10] JSON output exists and is valid.")
        except FileNotFoundError:
            feedback.append("[0] JSON output not found.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        except Exception as e:
            feedback.append(f"[0] JSON is invalid: {e}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 3. Check PNG Plot (10 pts)
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp:
        try:
            copy_from_env('/home/ga/pebl/analysis/capacity_plot.png', tmp.name)
            size = os.path.getsize(tmp.name)
            if size > 1024: # Minimum valid image size
                score += 10
                feedback.append("[+10] Capacity plot PNG generated successfully.")
            else:
                feedback.append("[0] Capacity plot PNG exists but is abnormally small (invalid).")
        except FileNotFoundError:
            feedback.append("[0] Capacity plot PNG not found.")
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # 4. Outlier Detection (20 pts)
    participants = report.get("participants", [])
    part_map = {}
    for p in participants:
        pid = p.get("id") or p.get("subject_id")
        if pid:
            part_map[pid] = p

    cheater = part_map.get("MOT_99", {})
    if cheater.get("excluded") in [True, "true", "True", 1]:
        score += 20
        feedback.append("[+20] Cheater (MOT_99) correctly identified and excluded.")
    else:
        feedback.append("[0] Cheater (MOT_99) NOT flagged as excluded.")

    # 5. Participant Math (30 pts)
    math_correct = 0
    total_checks = 0
    for pid, gt_stats in gt["participants"].items():
        if pid == "MOT_99":
            continue
        agent_stats = part_map.get(pid, {})
        agent_k = agent_stats.get("k_capacity", {})
        
        for tc in ["2", "3", "4", "5", "6"]:
            total_checks += 1
            agt_val = agent_k.get(tc)
            gt_val = gt_stats["k_capacity"][tc]
            if agt_val is not None:
                try:
                    if abs(float(agt_val) - gt_val) <= 0.05:
                        math_correct += 1
                except (ValueError, TypeError):
                    pass

    participant_score = int((math_correct / max(1, total_checks)) * 30)
    score += participant_score
    feedback.append(f"[+{participant_score}] Participant capacities correct ({math_correct}/{total_checks} conditions matched).")

    # 6. Group Math (30 pts)
    group_correct = 0
    agent_group = report.get("group_mean_capacity") or report.get("group_means", {})
    
    for tc in ["2", "3", "4", "5", "6"]:
        agt_val = agent_group.get(tc)
        gt_val = gt["group_means"][tc]
        if agt_val is not None:
            try:
                if abs(float(agt_val) - gt_val) <= 0.05:
                    group_correct += 1
            except (ValueError, TypeError):
                pass

    group_score = int((group_correct / 5) * 30)
    score += group_score
    feedback.append(f"[+{group_score}] Group capacities correct ({group_correct}/5 conditions matched).")

    # Pass Criteria Check
    key_criteria_met = (cheater.get("excluded") in [True, "true", "True", 1]) and (participant_score >= 15)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }