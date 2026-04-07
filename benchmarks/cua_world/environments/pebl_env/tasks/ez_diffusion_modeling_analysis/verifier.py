#!/usr/bin/env python3
"""
Verifier for EZ-Diffusion Modeling Analysis task.

Scoring (100 pts total):
  1. File Validity: Valid JSON output found (10 pts)
  2. Contamination Handling: sub-999 correctly excluded (20 pts)
  3. Unit Conversion: Reaction times correctly scaled to seconds (20 pts)
  4. Edge Correction: Correct finite parameters for 100% accuracy participant (20 pts)
  5. Parameter Accuracy: Individual parameters within 0.01 tolerance of GT (20 pts)
  6. Group Means: Group condition means within 0.01 tolerance of GT (10 pts)

Pass threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ez_diffusion_modeling_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the safely combined JSON object created in export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    output_exists = result.get("output_exists", False)
    agent_report = result.get("agent_report")
    gt = result.get("ground_truth", {})
    
    # --- Criterion 1: File Validity ---
    if not output_exists or not agent_report:
        return {"passed": False, "score": 0, "feedback": "Output file not found or contains invalid JSON."}
        
    score += 10
    feedback_parts.append("[+10] File is valid JSON.")
    
    # Process participant list into a map
    agent_ppts = agent_report.get("participants", [])
    part_map = {}
    for p in agent_ppts:
        pid = p.get("id") or p.get("participant_id") or p.get("participant")
        if pid:
            part_map[pid] = p

    # --- Criterion 2: Contamination Handling ---
    sub999 = part_map.get("sub-999", {})
    if sub999.get("excluded") in (True, "true", 1, "yes"):
        score += 20
        feedback_parts.append("[+20] sub-999 correctly excluded.")
    else:
        if "sub-999" not in part_map and "sub-999" in agent_report.get("excluded", []):
            score += 20
            feedback_parts.append("[+20] sub-999 correctly excluded in global list.")
        elif "sub-999" not in part_map:
             score += 20
             feedback_parts.append("[+20] sub-999 correctly omitted from results.")
        else:
            feedback_parts.append("[0] sub-999 not excluded despite VRT=0.")

    # --- Criterion 3: Unit Conversion ---
    # Non-decision time (Ter) in ms would be >100. In seconds it will be ~0.2 - 0.6.
    ter_vals = []
    for pid, data in part_map.items():
        if pid == "sub-999" or data.get("excluded"): continue
        for cond in ["Word_HighFreq", "Word_LowFreq"]:
            if cond in data and isinstance(data[cond], dict):
                ter = data[cond].get("Ter")
                if ter is not None:
                    try:
                        ter_vals.append(float(ter))
                    except ValueError:
                        pass
    
    if ter_vals and all(t < 5.0 for t in ter_vals):
        score += 20
        feedback_parts.append("[+20] Reaction times correctly converted to seconds.")
    else:
        feedback_parts.append("[0] Parameters suggest reaction times were not converted to seconds.")

    # --- Criterion 4: Edge Correction ---
    # sub-01 Word_HighFreq has 100% accuracy. Missing edge correction causes crash/NaN.
    sub01 = part_map.get("sub-01", {})
    edge_passed = False
    if sub01 and not sub01.get("excluded"):
        whf = sub01.get("Word_HighFreq", {})
        if isinstance(whf, dict):
            v = whf.get("v")
            if v is not None:
                try:
                    v_float = float(v)
                    gt_v = gt["participants"]["sub-01"]["Word_HighFreq"]["v"]
                    if abs(v_float - gt_v) < 0.05:
                        edge_passed = True
                except (ValueError, TypeError, KeyError):
                    pass
    if edge_passed:
        score += 20
        feedback_parts.append("[+20] Edge correction applied correctly for 100% accuracy.")
    else:
        feedback_parts.append("[0] Edge correction failed for sub-01 (100% accuracy constraint).")

    # --- Criterion 5: Parameter Accuracy ---
    gt_ppts = gt.get("participants", {})
    total_params = 0
    correct_params = 0
    
    for pid, gt_data in gt_ppts.items():
        if pid == "sub-999": continue
        agent_p = part_map.get(pid, {})
        for cond in ["Word_HighFreq", "Word_LowFreq"]:
            gt_cond = gt_data.get(cond, {})
            agent_cond = agent_p.get(cond, {})
            if isinstance(agent_cond, dict):
                for param in ["v", "a", "Ter"]:
                    gt_val = gt_cond.get(param)
                    agent_val = agent_cond.get(param)
                    total_params += 1
                    if agent_val is not None and gt_val is not None:
                        try:
                            if abs(float(agent_val) - gt_val) <= 0.01:
                                correct_params += 1
                        except ValueError:
                            pass
                            
    if total_params > 0:
        ratio = correct_params / total_params
        if ratio >= 0.8:
            score += 20
            feedback_parts.append("[+20] Individual parameters accurately match ground truth.")
        elif ratio >= 0.4:
            score += 10
            feedback_parts.append(f"[+10] Individual parameters partially match ({correct_params}/{total_params}).")
        else:
            feedback_parts.append(f"[0] Individual parameters mostly incorrect ({correct_params}/{total_params}).")

    # --- Criterion 6: Group Means ---
    agent_means = agent_report.get("group_means", {})
    gt_means = gt.get("group_means", {})
    mean_correct = 0
    mean_total = 0
    
    for cond in ["Word_HighFreq", "Word_LowFreq"]:
        if cond in gt_means and cond in agent_means:
            for param in ["v", "a", "Ter"]:
                key1 = f"mean_{param}"
                key2 = param
                gt_val = gt_means[cond].get(key1)
                
                agent_val = agent_means[cond].get(key1)
                if agent_val is None:
                    agent_val = agent_means[cond].get(key2)
                    
                mean_total += 1
                if agent_val is not None and gt_val is not None:
                    try:
                        if abs(float(agent_val) - gt_val) <= 0.01:
                            mean_correct += 1
                    except ValueError:
                        pass
                        
    if mean_total > 0 and mean_correct == mean_total:
        score += 10
        feedback_parts.append("[+10] Group means match ground truth.")
    elif mean_total > 0 and mean_correct >= mean_total / 2:
        score += 5
        feedback_parts.append(f"[+5] Group means partially correct ({mean_correct}/{mean_total}).")
    else:
        feedback_parts.append("[0] Group means incorrect or missing.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }