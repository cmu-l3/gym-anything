#!/usr/bin/env python3
"""
Verifier for lexdec_priming_analysis task.
"""
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lexdec_priming_analysis(traj, env_info, task_info):
    """
    Scoring Method:
      - Valid JSON Report (+10 pts)
      - Contaminated responder sub-99 correctly excluded (+25 pts)
      - All 20 remaining valid participants tracked (+10 pts)
      - Computed priming_effect_ms robust against tolerance (+20 pts)
      - Computed d_prime mapping hits/FA robust against tolerance (+15 pts)
      - Group mean cross-validation (+20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Anti-gaming File Time Check
    task_res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified_during_task = False
    try:
        copy_from_env("/tmp/task_result.json", task_res_file.name)
        with open(task_res_file.name, 'r') as f:
            task_res = json.load(f)
            file_modified_during_task = task_res.get("file_modified_during_task", False)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        os.unlink(task_res_file.name)

    # 2. Read Ground Truth
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = None
    try:
        copy_from_env("/var/lib/pebl/ground_truth/priming_ground_truth.json", gt_file.name)
        with open(gt_file.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read ground truth: {e}"}
    finally:
        os.unlink(gt_file.name)

    # 3. Process Agent's Generated Report
    report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report = None
    try:
        copy_from_env("/home/ga/pebl/analysis/priming_report.json", report_file.name)
        with open(report_file.name, 'r') as f:
            report = json.load(f)
        score += 10
        feedback.append("[+10] Output file exists and is valid JSON.")
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/pebl/analysis/priming_report.json not found."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Output file is not valid JSON: {e}"}
    finally:
        os.unlink(report_file.name)

    if not file_modified_during_task:
        feedback.append("[-] CRITICAL WARNING: Output file was not created/modified during task.")

    participants = report.get("participants", [])
    if not isinstance(participants, list):
        return {"passed": False, "score": score, "feedback": " ".join(feedback) + " 'participants' key missing or not a list."}

    # Helper lookup
    def get_p(pid):
        for p in participants:
            p_id = p.get("id", p.get("participant_id", p.get("participant")))
            if str(p_id) == pid:
                return p
        return None

    # Criterion A: Exclusion Logic
    sub99 = get_p("sub-99")
    if sub99 and sub99.get("excluded", False):
        score += 25
        feedback.append("[+25] sub-99 correctly excluded.")
    else:
        excluded_list = report.get("excluded", [])
        if isinstance(excluded_list, list) and "sub-99" in excluded_list:
            score += 25
            feedback.append("[+25] sub-99 correctly excluded.")
        else:
            feedback.append("[0] sub-99 not correctly excluded despite chance accuracy and null effect.")

    # Criterion B: Participant Accuracies 
    valid_ids = [f"sub-{i:02d}" for i in range(1, 21)]
    valid_found = 0
    priming_correct = 0
    dprime_correct = 0

    for pid in valid_ids:
        p_data = get_p(pid)
        if p_data and not p_data.get("excluded", False):
            valid_found += 1
            
            # Sub-Criterion B.1: Check Priming Effects
            gt_priming = gt["participants"][pid]["priming_effect_ms"]
            rep_priming = p_data.get("priming_effect_ms", p_data.get("priming_effect", p_data.get("priming")))
            if rep_priming is not None:
                try:
                    if abs(float(rep_priming) - gt_priming) <= 15:
                        priming_correct += 1
                except ValueError:
                    pass

            # Sub-Criterion B.2: Check Signal Detection Theory Values (d')
            gt_dp = gt["participants"][pid]["d_prime"]
            rep_dp = p_data.get("d_prime", p_data.get("dprime", p_data.get("d'")))
            if rep_dp is not None:
                try:
                    if abs(float(rep_dp) - gt_dp) <= 0.5:
                        dprime_correct += 1
                except ValueError:
                    pass

    # Record Participant Presence Result
    if valid_found == 20:
        score += 10
        feedback.append("[+10] All 20 valid participants present.")
    else:
        feedback.append(f"[0] Only {valid_found}/20 valid participants present.")

    # Record Calculation Accuracies
    if priming_correct >= 15:
        score += 20
        feedback.append(f"[+20] Priming effect accurate for {priming_correct}/20 participants.")
    elif priming_correct >= 10:
        score += 10
        feedback.append(f"[+10] Priming effect accurate for {priming_correct}/20 participants (partial).")
    else:
        feedback.append(f"[0] Priming effect accurate for {priming_correct}/20 participants.")

    if dprime_correct >= 15:
        score += 15
        feedback.append(f"[+15] d' accurate for {dprime_correct}/20 participants.")
    elif dprime_correct >= 10:
        score += 8
        feedback.append(f"[+8] d' accurate for {dprime_correct}/20 participants (partial).")
    else:
        feedback.append(f"[0] d' accurate for {dprime_correct}/20 participants.")

    # Criterion C: Group Demographics Validation
    group_means = report.get("group_means", {})
    if group_means:
        gt_gm = gt["group_means"]
        
        rep_gm_priming = group_means.get("mean_priming_effect_ms", group_means.get("mean_priming_effect", group_means.get("priming_effect")))
        if rep_gm_priming is not None:
            try:
                if abs(float(rep_gm_priming) - gt_gm["mean_priming_effect_ms"]) <= 10:
                    score += 10
                    feedback.append("[+10] Group mean priming effect accurate.")
                else:
                    feedback.append("[0] Group mean priming effect inaccurate.")
            except ValueError:
                feedback.append("[0] Group mean priming is not a valid number.")
        else:
            feedback.append("[0] Group mean priming missing.")

        rep_gm_dp = group_means.get("mean_d_prime", group_means.get("mean_dprime", group_means.get("d_prime")))
        if rep_gm_dp is not None:
            try:
                if abs(float(rep_gm_dp) - gt_gm["mean_d_prime"]) <= 0.3:
                    score += 10
                    feedback.append("[+10] Group mean d' accurate.")
                else:
                    feedback.append("[0] Group mean d' inaccurate.")
            except ValueError:
                feedback.append("[0] Group mean d' is not a valid number.")
        else:
            feedback.append("[0] Group mean d' missing.")
    else:
        feedback.append("[0] 'group_means' dictionary mapping missing.")

    passed = (score >= 60) and file_modified_during_task
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }