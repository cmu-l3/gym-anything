#!/usr/bin/env python3
"""
Verifier for Measure Dust Optical Depth task.
"""

import os
import json
import re
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optical_depth(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ==========================================
    # Load agent's result file
    # ==========================================
    res_path = "/tmp/task_result.json"
    local_res = "/tmp/local_result.json"
    try:
        copy_from_env(res_path, local_res)
        with open(local_res, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load agent's result: {e}"}
    finally:
        if os.path.exists(local_res):
            os.remove(local_res)
        
    # ==========================================
    # Load dynamically generated ground truth
    # ==========================================
    gt_path = "/tmp/ground_truth.json"
    local_gt = "/tmp/local_gt.json"
    try:
        copy_from_env(gt_path, local_gt)
        with open(local_gt, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(local_gt):
            os.remove(local_gt)
        
    score = 0
    feedback_parts = []
    
    file_exists = result.get('file_exists', False)
    content = result.get('file_content', '')
    
    # Check if report file was even created
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
        
    score += 10
    feedback_parts.append("Report file exists (+10)")
    
    # Parse file contents via regex
    reported_pillar = None
    m1 = re.search(r'I_pillar:\s*([0-9.]+)', content)
    if m1: reported_pillar = float(m1.group(1))
    
    reported_bg = None
    m2 = re.search(r'I_background:\s*([0-9.]+)', content)
    if m2: reported_bg = float(m2.group(1))
    
    reported_trans = None
    m3 = re.search(r'Transmission:\s*([0-9.]+)', content)
    if m3: reported_trans = float(m3.group(1))
    
    reported_od = None
    m4 = re.search(r'Optical_Depth:\s*([0-9.]+)', content)
    if m4: reported_od = float(m4.group(1))
    
    # ==========================================
    # Math & Extraction Checks
    # ==========================================
    
    # Check Pillar Flux Accuracy (within 5% tolerance)
    if reported_pillar is not None:
        if abs(reported_pillar - gt['i_pillar']) / max(1e-6, gt['i_pillar']) <= 0.05:
            score += 20
            feedback_parts.append("I_pillar correct (+20)")
        else:
            feedback_parts.append(f"I_pillar incorrect (expected {gt['i_pillar']:.2f}, got {reported_pillar})")
    else:
        feedback_parts.append("I_pillar not found in report")
        
    # Check Background Flux Accuracy (within 5% tolerance)
    if reported_bg is not None:
        if abs(reported_bg - gt['i_bg']) / max(1e-6, gt['i_bg']) <= 0.05:
            score += 20
            feedback_parts.append("I_background correct (+20)")
        else:
            feedback_parts.append(f"I_background incorrect (expected {gt['i_bg']:.2f}, got {reported_bg})")
    else:
        feedback_parts.append("I_background not found in report")
        
    # Check Transmission Calculation Math (based on agent's extracted numbers if possible, otherwise GT)
    if reported_pillar is not None and reported_bg is not None and reported_trans is not None:
        expected_t_own = reported_pillar / max(1e-6, reported_bg)
        if abs(reported_trans - expected_t_own) <= 0.02:
            score += 20
            feedback_parts.append("Transmission math correct (+20)")
        else:
            feedback_parts.append(f"Transmission math incorrect (expected {expected_t_own:.3f}, got {reported_trans})")
    elif reported_trans is not None:
        # Fallback to GT if they didn't write component fluxes
        if abs(reported_trans - gt['transmission']) <= 0.02:
            score += 20
            feedback_parts.append("Transmission correct (+20)")
        else:
            feedback_parts.append("Transmission incorrect")
            
    # Check Optical Depth Calculation Math (based on agent's transmission, otherwise GT)
    if reported_trans is not None and reported_od is not None:
        if reported_trans > 0:
            expected_od_own = -math.log(reported_trans)
            if abs(reported_od - expected_od_own) <= 0.05:
                score += 30
                feedback_parts.append("Optical Depth math correct (+30)")
            else:
                feedback_parts.append(f"Optical Depth math incorrect (expected {expected_od_own:.3f}, got {reported_od})")
    elif reported_od is not None:
        if abs(reported_od - gt['optical_depth']) <= 0.05:
            score += 30
            feedback_parts.append("Optical Depth correct (+30)")
        else:
            feedback_parts.append("Optical Depth incorrect")
            
    # Calculate threshold (70 points required)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }