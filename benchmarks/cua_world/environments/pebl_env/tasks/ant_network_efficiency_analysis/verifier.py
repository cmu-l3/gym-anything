#!/usr/bin/env python3
"""
Verifier for ant_network_efficiency_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Contaminated participant sub-99 is excluded with reason       (20 pts)
  3. All 20 real participants present in report                    (10 pts)
  4. Alerting score within ±12ms for ≥16 valid ppts                (15 pts)
  5. Orienting score within ±12ms for ≥16 valid ppts               (15 pts)
  6. Executive score within ±12ms for ≥16 valid ppts               (15 pts)
  7. Group mean Alerting within ±8ms of ground truth               (5 pts)
  8. Group mean Orienting within ±8ms of ground truth              (5 pts)
  9. Group mean Executive within ±8ms of ground truth              (5 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ant_network_efficiency_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    metadata = task_info.get('metadata', {})
    indiv_tolerance = metadata.get('tolerances', {}).get('individual_score_ms', 12.0)
    group_tolerance = metadata.get('tolerances', {}).get('group_mean_ms', 8.0)
    contaminated_participant = metadata.get('contaminated_participant', 'sub-99')
    
    score = 0
    feedback_parts = []

    # --- Load Ground Truth ---
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_gt:
        tmp_gt_path = tmp_gt.name
        
    try:
        copy_from_env('/var/lib/pebl_ground_truth/ant_ground_truth.json', tmp_gt_path)
        with open(tmp_gt_path, 'r', encoding='utf-8') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(tmp_gt_path):
            os.unlink(tmp_gt_path)

    # --- Criterion 1: Output file exists and is valid JSON (10 pts) ---
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_rep:
        tmp_rep_path = tmp_rep.name

    try:
        copy_from_env('/home/ga/pebl/analysis/ant_report.json', tmp_rep_path)
        with open(tmp_rep_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output file is valid JSON.")
    except FileNotFoundError:
        feedback_parts.append("[0] Output file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f"[0] Output file invalid JSON: {e}")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}
    finally:
        if os.path.exists(tmp_rep_path):
            os.unlink(tmp_rep_path)

    participants_list = report.get('participants', [])
    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        if pid not in part_map:
            excluded_list = report.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
        return False

    def get_val(entry, keys):
        for k in keys:
            if k in entry and entry[k] is not None:
                try:
                    return float(entry[k])
                except (ValueError, TypeError):
                    continue
        return None

    # --- Criterion 2: Contaminated participant excluded (20 pts) ---
    if is_excluded(contaminated_participant):
        score += 20
        feedback_parts.append(f"[+20] {contaminated_participant} correctly excluded.")
    else:
        feedback_parts.append(f"[0] {contaminated_participant} not excluded.")

    # --- Criterion 3: All 20 real participants present (10 pts) ---
    gt_pids = set(gt['participants'].keys())
    present_pids = gt_pids.intersection(part_map.keys())
    
    if len(present_pids) == 20:
        score += 10
        feedback_parts.append("[+10] All 20 real participants present.")
    elif len(present_pids) > 0:
        partial = int((len(present_pids) / 20) * 10)
        score += partial
        feedback_parts.append(f"[+{partial}] {len(present_pids)}/20 real participants present.")
    else:
        feedback_parts.append("[0] No valid participants found in report.")

    # --- Criteria 4, 5, 6: Network scores per participant (15 pts each) ---
    correct_alerting = 0
    correct_orienting = 0
    correct_executive = 0
    
    for pid, gt_scores in gt['participants'].items():
        entry = part_map.get(pid)
        if entry is None or is_excluded(pid):
            continue
            
        alerting = get_val(entry, ['alerting_ms', 'alerting', 'Alerting', 'alerting_score'])
        orienting = get_val(entry, ['orienting_ms', 'orienting', 'Orienting', 'orienting_score'])
        executive = get_val(entry, ['executive_ms', 'executive', 'Executive', 'executive_score', 'conflict_ms', 'conflict'])
        
        if alerting is not None and abs(alerting - gt_scores['alerting_ms']) <= indiv_tolerance:
            correct_alerting += 1
        if orienting is not None and abs(orienting - gt_scores['orienting_ms']) <= indiv_tolerance:
            correct_orienting += 1
        if executive is not None and abs(executive - gt_scores['executive_ms']) <= indiv_tolerance:
            correct_executive += 1

    # Alerting (15 pts)
    if correct_alerting >= 16:
        score += 15
        feedback_parts.append(f"[+15] Alerting accurate for {correct_alerting}/20 ppts.")
    elif correct_alerting >= 10:
        score += 7
        feedback_parts.append(f"[+7] Alerting accurate for {correct_alerting}/20 ppts (partial).")
    else:
        feedback_parts.append(f"[0] Alerting accurate for only {correct_alerting}/20 ppts.")

    # Orienting (15 pts)
    if correct_orienting >= 16:
        score += 15
        feedback_parts.append(f"[+15] Orienting accurate for {correct_orienting}/20 ppts.")
    elif correct_orienting >= 10:
        score += 7
        feedback_parts.append(f"[+7] Orienting accurate for {correct_orienting}/20 ppts (partial).")
    else:
        feedback_parts.append(f"[0] Orienting accurate for only {correct_orienting}/20 ppts.")

    # Executive (15 pts)
    if correct_executive >= 16:
        score += 15
        feedback_parts.append(f"[+15] Executive accurate for {correct_executive}/20 ppts.")
    elif correct_executive >= 10:
        score += 7
        feedback_parts.append(f"[+7] Executive accurate for {correct_executive}/20 ppts (partial).")
    else:
        feedback_parts.append(f"[0] Executive accurate for only {correct_executive}/20 ppts.")

    # --- Criteria 7, 8, 9: Group means (5 pts each) ---
    group = report.get('group_means', {})
    if not isinstance(group, dict):
        group = report  # Fallback if agent put them at top level
        
    g_alerting = get_val(group, ['alerting_ms', 'alerting', 'mean_alerting'])
    g_orienting = get_val(group, ['orienting_ms', 'orienting', 'mean_orienting'])
    g_executive = get_val(group, ['executive_ms', 'executive', 'mean_executive', 'conflict_ms'])
    
    gt_group = gt['group_means']
    
    if g_alerting is not None and abs(g_alerting - gt_group['alerting_ms']) <= group_tolerance:
        score += 5
        feedback_parts.append("[+5] Group Alerting correct.")
    else:
        feedback_parts.append(f"[0] Group Alerting incorrect/missing (expected ~{gt_group['alerting_ms']:.1f}).")

    if g_orienting is not None and abs(g_orienting - gt_group['orienting_ms']) <= group_tolerance:
        score += 5
        feedback_parts.append("[+5] Group Orienting correct.")
    else:
        feedback_parts.append(f"[0] Group Orienting incorrect/missing (expected ~{gt_group['orienting_ms']:.1f}).")

    if g_executive is not None and abs(g_executive - gt_group['executive_ms']) <= group_tolerance:
        score += 5
        feedback_parts.append("[+5] Group Executive correct.")
    else:
        feedback_parts.append(f"[0] Group Executive incorrect/missing (expected ~{gt_group['executive_ms']:.1f}).")

    passed = score >= 60 and is_excluded(contaminated_participant)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }