#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_optimize_sky_annulus(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Load results from the container
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result reading error: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Load the dynamic ground truth from the container
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/photometry_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"GT reading error: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    score = 0
    feedback = []

    # Criterion 1: Output files existence
    if result.get('csv_exists') and result.get('txt_exists'):
        score += 10
        feedback.append("Both expected output files found.")
        
        # Anti-gaming: Ensure files were created during the task
        if not result.get('csv_created_during_task') or not result.get('txt_created_during_task'):
            feedback.append("Warning: Files appear to have been created before the task started.")
    else:
        feedback.append("Missing one or both expected output files.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    csv_content = result.get('csv_content', '')
    txt_content = result.get('txt_content', '')

    # Parse agent's CSV
    agent_configs = {}
    for line in csv_content.split('\n'):
        parts = [p.strip() for p in line.split(',')]
        if len(parts) >= 3:
            cfg_id = parts[0].upper()
            if 'A' in cfg_id or '15' in cfg_id:
                cfg = 'A'
            elif 'B' in cfg_id or '25' in cfg_id:
                cfg = 'B'
            elif 'C' in cfg_id or '40' in cfg_id:
                cfg = 'C'
            else:
                continue

            try:
                sky = float(parts[1])
                net = float(parts[2])
                agent_configs[cfg] = {'sky': sky, 'net': net}
            except ValueError:
                pass  # Ignore headers or malformed rows

    # Evaluate configs against dynamically generated Ground Truth
    configs_to_check = ['A', 'B', 'C']
    all_configs_valid = True
    
    for cfg in configs_to_check:
        if cfg in agent_configs and cfg in gt.get('configs', {}):
            agent_sky = agent_configs[cfg]['sky']
            agent_net = agent_configs[cfg]['net']
            gt_sky = gt['configs'][cfg]['sky_per_pixel']
            gt_net = gt['configs'][cfg]['net_source_flux']

            # Tolerance is generous (25%) to account for AIJ's fractional pixel edge weighting vs pure numpy masks
            sky_err = abs(agent_sky - gt_sky) / max(1e-5, abs(gt_sky))
            net_err = abs(agent_net - gt_net) / max(1e-5, abs(gt_net))

            if sky_err < 0.25 and net_err < 0.25:
                score += 20
                feedback.append(f"Config {cfg} measurements accurate.")
            else:
                feedback.append(f"Config {cfg} values differ significantly (sky err: {sky_err:.1%}, net err: {net_err:.1%}).")
                all_configs_valid = False
        else:
            feedback.append(f"Config {cfg} not found or unparseable in CSV.")
            all_configs_valid = False

    # Evaluate conclusion text
    txt_lower = txt_content.lower()
    
    # Robust check using word boundaries
    identified_c = bool(re.search(r'\bc\b|40', txt_lower))
    identified_a = bool(re.search(r'\ba\b|15', txt_lower))

    if identified_c and identified_a:
        score += 30
        feedback.append("Conclusion correctly references C (most contaminated) and A (optimal).")
    elif identified_c:
        score += 15
        feedback.append("Conclusion referenced C, but missed A.")
    elif identified_a:
        score += 15
        feedback.append("Conclusion referenced A, but missed C.")
    else:
        feedback.append("Conclusion did not clearly identify A and C as answers.")

    # Determine pass state (Must hit at least 70 points to pass)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }