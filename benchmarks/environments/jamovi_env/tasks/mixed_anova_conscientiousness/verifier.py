#!/usr/bin/env python3
"""
Verifier for mixed_anova_conscientiousness task.
Verifies Jamovi output by parsing the agent's text report and comparing to pre-computed ground truth.
"""

import json
import os
import tempfile
import re
import math

def verify_mixed_anova(traj, env_info, task_info):
    """
    Verify the Mixed ANOVA task.
    
    Criteria:
    1. .omv file created and valid size (10 pts)
    2. Report file created and contains required fields (10 pts)
    3. Statistics match ground truth (80 pts total)
       - Item F, p (15, 10)
       - Gender F, p (15, 5)
       - Interaction F, p (15, 5)
       - Epsilon (10)
       - Mauchly sig (5)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_log = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Artifacts
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    task_result = {}
    ground_truth = {}
    report_content = ""
    
    try:
        # Get result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
            
        # Get Ground Truth
        # The export script copies it to /tmp/mixed_anova_ground_truth.json
        if task_result.get("ground_truth_path"):
            copy_from_env(task_result["ground_truth_path"], temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                ground_truth = json.load(f)
        
        # Get Agent Report
        if task_result.get("report_exists"):
            copy_from_env(task_result["report_path"], temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving files: {e}"}
    finally:
        for tmp in [temp_result, temp_gt, temp_report]:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # ------------------------------------------------------------------
    # 2. Check File Existence (20 pts)
    # ------------------------------------------------------------------
    # Check OMV
    if task_result.get("omv_exists") and task_result.get("omv_created_during_task"):
        if task_result.get("omv_size_bytes", 0) > 1000: # Arbitrary small threshold for valid zip
            score += 10
            feedback_log.append("PASS: .omv project file saved.")
        else:
            feedback_log.append("FAIL: .omv file is too small/empty.")
    else:
        feedback_log.append("FAIL: .omv file not created or not saved during task.")

    # Check Report Existence
    if task_result.get("report_exists") and task_result.get("report_created_during_task"):
        score += 10
        feedback_log.append("PASS: Report text file saved.")
    else:
        feedback_log.append("FAIL: Report text file missing.")
        # Cannot verify content without file
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_log)}

    # ------------------------------------------------------------------
    # 3. Parse Report Content
    # ------------------------------------------------------------------
    parsed_report = {}
    try:
        lines = report_content.strip().split('\n')
        for line in lines:
            if ':' in line:
                key, val = line.split(':', 1)
                parsed_report[key.strip()] = val.strip()
    except Exception as e:
        feedback_log.append(f"WARNING: Error parsing report structure: {e}")

    # Helper for comparison
    def check_val(key, tolerance_rel=0.15, tolerance_abs=0.01, is_p=False):
        if key not in parsed_report or key not in ground_truth:
            return False, f"Missing {key}"
            
        try:
            # Handle string values like "< 0.001"
            agent_str = parsed_report[key]
            gt_val = ground_truth[key]
            
            # Special case for small p-values
            if is_p and gt_val < 0.001:
                if "<" in agent_str and ("0.001" in agent_str or ".001" in agent_str):
                    return True, f"{key} correct (< 0.001)"
                # If they reported a specific number anyway
                try:
                    val = float(re.sub(r'[^\d\.]', '', agent_str))
                    if val < 0.001:
                        return True, f"{key} correct (value < 0.001)"
                except:
                    pass
            
            # Numeric parsing
            agent_val = float(re.sub(r'[^\d\.-]', '', agent_str))
            
            diff = abs(agent_val - gt_val)
            
            # Check tolerances
            passed = False
            if gt_val == 0:
                 passed = diff <= tolerance_abs
            else:
                 rel_diff = diff / abs(gt_val)
                 passed = (diff <= tolerance_abs) or (rel_diff <= tolerance_rel)
            
            return passed, f"{key}: Agent={agent_val}, GT={gt_val:.4f}"
            
        except ValueError:
            return False, f"Could not parse numeric value for {key}: '{parsed_report[key]}'"

    # ------------------------------------------------------------------
    # 4. Verify Values (80 pts)
    # ------------------------------------------------------------------
    
    # Main Effect CItem (Item)
    ok_f, msg_f = check_val("Item_F", tolerance_rel=0.15) # F stats can vary slightly between implementations
    if ok_f: score += 15
    feedback_log.append(msg_f)
    
    ok_p, msg_p = check_val("Item_p", is_p=True)
    if ok_p: score += 10
    feedback_log.append(msg_p)
    
    # Main Effect Gender
    ok_f, msg_f = check_val("Gender_F", tolerance_rel=0.15)
    if ok_f: score += 15
    feedback_log.append(msg_f)
    
    ok_p, msg_p = check_val("Gender_p", is_p=True)
    if ok_p: score += 5
    feedback_log.append(msg_p)
    
    # Interaction
    ok_f, msg_f = check_val("Interaction_F", tolerance_rel=0.15)
    if ok_f: score += 15
    feedback_log.append(msg_f)
    
    ok_p, msg_p = check_val("Interaction_p", is_p=True)
    if ok_p: score += 5
    feedback_log.append(msg_p)
    
    # Epsilon
    ok_eps, msg_eps = check_val("GG_epsilon", tolerance_abs=0.05)
    if ok_eps: score += 10
    feedback_log.append(msg_eps)
    
    # Mauchly
    agent_mauchly = parsed_report.get("Mauchly_significant", "").lower()
    gt_mauchly = ground_truth.get("Mauchly_significant", "").lower()
    if agent_mauchly == gt_mauchly and gt_mauchly in ['yes', 'no']:
        score += 5
        feedback_log.append(f"Mauchly sig correct: {agent_mauchly}")
    else:
        feedback_log.append(f"Mauchly sig mismatch: Agent={agent_mauchly}, GT={gt_mauchly}")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }