#!/usr/bin/env python3
"""
Verifier for snarc_effect_regression_analysis task.

Scoring (100 pts total):
  1. File exists, created during task, and is valid JSON            (10 pts)
  2. Contaminated participant (sub-99) is successfully excluded     (20 pts)
  3. Mean accuracy calculated correctly for valid participants      (15 pts)
  4. SNARC slopes calculated correctly for valid participants       (35 pts)
  5. Group mean SNARC slope calculated correctly                    (20 pts)

Anti-gaming:
  - File must have a modification timestamp > task start time.
  - Strict ±0.5 tolerance on the linear regression slopes to ensure 
    actual calculation was performed.
"""

import json
import os
import tempfile

CONTAMINATED_PARTICIPANT = 'sub-99'
ACC_TOLERANCE = 0.02
SLOPE_TOLERANCE = 0.5
PASS_THRESHOLD = 65

def verify_snarc_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy mechanism missing."}
        
    score = 0
    feedback_parts = []

    # ==========================================
    # 0. Check task metadata & Anti-gaming
    # ==========================================
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        meta_tmp = tmp.name
        
    try:
        copy_from_env('/tmp/task_result.json', meta_tmp)
        with open(meta_tmp, 'r') as f:
            metadata = json.load(f)
    except Exception:
        return {"passed": False, "score": 0, "feedback": "Failed to read task export metadata."}
    finally:
        if os.path.exists(meta_tmp):
            os.unlink(meta_tmp)

    if not metadata.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file snarc_report.json not found."}
        
    if not metadata.get('file_created_during_task'):
        feedback_parts.append("[0] WARNING: Output file existed before task started (Anti-gaming check failed).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ==========================================
    # 1. Check Output JSON validity
    # ==========================================
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        report_tmp = tmp.name

    try:
        copy_from_env('/home/ga/pebl/analysis/snarc_report.json', report_tmp)
        with open(report_tmp, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] Output file found and is valid JSON.")
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f"[0] Output file is not valid JSON: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    finally:
        if os.path.exists(report_tmp):
            os.unlink(report_tmp)

    # ==========================================
    # Load Ground Truth
    # ==========================================
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        gt_tmp = tmp.name
        
    try:
        copy_from_env('/tmp/gt_snarc.json', gt_tmp)
        with open(gt_tmp, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Ground truth missing: {e}"}
    finally:
        if os.path.exists(gt_tmp):
            os.unlink(gt_tmp)

    # Build agent map
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

    # ==========================================
    # 2. Contaminated participant excluded
    # ==========================================
    if is_excluded(CONTAMINATED_PARTICIPANT):
        score += 20
        feedback_parts.append(f"[+20] {CONTAMINATED_PARTICIPANT} correctly excluded.")
    else:
        feedback_parts.append(f"[0] {CONTAMINATED_PARTICIPANT} was not excluded despite invariant RTs.")

    # ==========================================
    # 3 & 4. Accurate Metrics per Participant
    # ==========================================
    correct_acc = 0
    correct_slope = 0
    gt_ppts = gt.get('participants', {})
    num_valid = len(gt_ppts)

    for pid, gt_vals in gt_ppts.items():
        entry = part_map.get(pid)
        if entry is None or is_excluded(pid):
            continue
            
        # Accuracy Check
        acc = entry.get('mean_accuracy') or entry.get('accuracy')
        if acc is not None:
            try:
                if abs(float(acc) - gt_vals['mean_accuracy']) <= ACC_TOLERANCE:
                    correct_acc += 1
            except ValueError:
                pass
                
        # Slope Check
        slope = entry.get('snarc_slope_ms_per_digit') or entry.get('snarc_slope') or entry.get('slope')
        if slope is not None:
            try:
                if abs(float(slope) - gt_vals['snarc_slope_ms_per_digit']) <= SLOPE_TOLERANCE:
                    correct_slope += 1
            except ValueError:
                pass

    if correct_acc >= (num_valid - 1):
        score += 15
        feedback_parts.append(f"[+15] Mean accuracy correct for {correct_acc}/{num_valid} valid participants.")
    elif correct_acc >= 5:
        score += 7
        feedback_parts.append(f"[+7] Mean accuracy partially correct ({correct_acc}/{num_valid}).")
    else:
        feedback_parts.append(f"[0] Mean accuracy mostly incorrect ({correct_acc}/{num_valid}).")

    if correct_slope >= (num_valid - 2):
        score += 35
        feedback_parts.append(f"[+35] SNARC slopes correct for {correct_slope}/{num_valid} valid participants.")
    elif correct_slope >= 5:
        score += 15
        feedback_parts.append(f"[+15] SNARC slopes partially correct ({correct_slope}/{num_valid}).")
    else:
        feedback_parts.append(f"[0] SNARC slopes mostly incorrect ({correct_slope}/{num_valid}).")

    # ==========================================
    # 5. Group Mean Slope
    # ==========================================
    group_slope = report.get('group_mean_snarc_slope') or report.get('group_mean_slope')
    gt_group_slope = gt.get('group_mean_snarc_slope')
    
    if group_slope is not None:
        try:
            if abs(float(group_slope) - gt_group_slope) <= SLOPE_TOLERANCE:
                score += 20
                feedback_parts.append(f"[+20] Group mean slope correct (Agent: {group_slope}, GT: {gt_group_slope}).")
            else:
                feedback_parts.append(f"[0] Group mean slope incorrect (Agent: {group_slope}, GT: {gt_group_slope}).")
        except ValueError:
            feedback_parts.append("[0] Group mean slope is not a valid number.")
    else:
        feedback_parts.append("[0] Group mean slope not found in report.")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }