#!/usr/bin/env python3
"""
Verifier for Isolate Cluster Core Stars Task.

Verifies:
1. Expected files exist (FITS & CSV).
2. FITS file retains structure/dimensions.
3. Mean of the output image is drastically reduced compared to the raw input (indicative of subtraction).
4. Gradient flattened: the difference between the core median and edge median should be 
   reduced by at least 85% compared to the original image gradient.
5. Point Sources Intact: Standard deviation > threshold to confirm the image is not completely empty.
6. CSV contains valid export structures including mean metrics.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_isolate_cluster_core_stars(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
        
    score = 0
    feedback = []

    # Copy result
    result = {}
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)
            
    # Copy ground truth
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/core_isolation_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Ground truth file error: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
            
    # 1. Output files exist (15 points)
    fits_exists = result.get("fits_exists", False)
    csv_exists = result.get("csv_exists", False)
    if fits_exists:
        score += 10
        feedback.append("FITS output found.")
    else:
        feedback.append("FITS output not found.")
        
    if csv_exists:
        score += 5
        feedback.append("CSV output found.")
    else:
        feedback.append("CSV output not found.")
        
    # 2. Valid FITS structure (10 points)
    if fits_exists and result.get("output_shape") == gt.get("input_shape"):
        score += 10
        feedback.append("Output FITS shape matches input.")
    elif fits_exists:
        feedback.append("Output FITS shape mismatch.")
        
    # 3. Mean reduction (15 points)
    out_mean = result.get("output_mean")
    in_mean = gt.get("input_mean")
    if out_mean is not None and in_mean is not None and in_mean > 0:
        if out_mean < in_mean * 0.20:
            score += 15
            feedback.append("Mean properly reduced (< 20% of original).")
        elif out_mean < in_mean * 0.50:
            score += 10
            feedback.append("Mean somewhat reduced (< 50% of original).")
        else:
            feedback.append("Mean not significantly reduced.")
            
    # 4. Gradient flattened (40 points)
    out_core = result.get("output_core_median")
    out_edge = result.get("output_edge_median")
    in_core = gt.get("input_core_median")
    in_edge = gt.get("input_edge_median")
    
    gradient_flattened_passed = False
    if all(x is not None for x in [out_core, out_edge, in_core, in_edge]):
        in_diff = abs(in_core - in_edge)
        out_diff = abs(out_core - out_edge)
        if in_diff > 0:
            reduction = 1 - (out_diff / in_diff)
            if reduction >= 0.85:
                score += 40
                gradient_flattened_passed = True
                feedback.append(f"Gradient excellently flattened (reduction: {reduction*100:.1f}%).")
            elif reduction >= 0.50:
                score += 20
                feedback.append(f"Gradient moderately flattened (reduction: {reduction*100:.1f}%).")
            elif reduction >= 0.20:
                score += 10
                feedback.append(f"Gradient slightly flattened (reduction: {reduction*100:.1f}%).")
            else:
                feedback.append(f"Gradient not flattened (reduction: {reduction*100:.1f}%).")
    else:
        feedback.append("Could not calculate gradient statistics.")
                
    # 5. Point sources intact (10 points)
    out_std = result.get("output_std")
    if out_std is not None and out_std > 1.0:
        score += 10
        feedback.append("Point sources likely intact (StdDev > 1.0).")
    elif out_std is not None:
        feedback.append("Image appears flat/empty (StdDev too low).")
        
    # 6. Results exported (10 points)
    if csv_exists and result.get("csv_has_mean"):
        score += 10
        feedback.append("CSV contains mean measurement.")
    elif csv_exists:
        score += 5
        feedback.append("CSV exists but mean measurement not detected.")
        
    # Validation constraint: Main scientific goal is flattening the gradient
    passed = score >= 70 and gradient_flattened_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }