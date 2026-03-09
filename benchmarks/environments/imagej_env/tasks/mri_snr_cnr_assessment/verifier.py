#!/usr/bin/env python3
"""
Verifier for MRI SNR/CNR Assessment task.

Scoring Criteria (100 pts total):
1. Result file exists & created during task: 15 pts
2. Three distinct regions (WM, GM, BG) identified in text: 20 pts
3. Mean Intensity Ordering (WM > GM > BG): 15 pts
   - Checks basic physics of T1-weighted MRI.
4. Standard Deviation present for BG: 10 pts
5. SNR/CNR Values Computed:
   - SNR_WM present and valid (>5): 10 pts
   - SNR_GM present and valid (>5): 10 pts
   - CNR present and valid (>1): 20 pts

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mri_snr_cnr(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mri_snr_cnr_assessment_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file not found or invalid: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    passed = False

    # 1. File Existence and Timestamp (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback.append("Result file created successfully.")
    else:
        feedback.append("Result file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Regions Found (20 pts)
    regions = result.get("regions_found", [])
    if len(regions) >= 3:
        score += 20
        feedback.append(f"All 3 regions identified: {', '.join(regions)}.")
    elif len(regions) > 0:
        score += 10
        feedback.append(f"Partial regions identified: {', '.join(regions)}. Need WM, GM, BG.")
    else:
        feedback.append("No distinct tissue regions (WM, GM, BG) identified in output.")

    # 3. Intensity Ordering / Physics Check (15 pts)
    meas = result.get("measurements", {})
    mean_wm = meas.get("mean_wm", 0)
    mean_gm = meas.get("mean_gm", 0)
    mean_bg = meas.get("mean_bg", 0)
    
    # Check if we successfully extracted numbers
    if mean_wm > 0 and mean_gm > 0:
        if mean_wm > mean_gm:
            # T1 physics: White Matter is brighter than Gray Matter
            if mean_gm > mean_bg: 
                score += 15
                feedback.append("Tissue intensity physics valid (WM > GM > BG).")
            else:
                score += 10
                feedback.append("Tissue intensity valid (WM > GM), but BG seems high.")
        else:
            feedback.append(f"Intensity physics violation: WM ({mean_wm}) should be > GM ({mean_gm}) in T1.")
    else:
        feedback.append("Could not extract mean intensities for verification.")

    # 4. Background Noise Measurement (10 pts)
    std_bg = meas.get("std_bg", 0)
    if std_bg > 0:
        score += 10
        feedback.append(f"Background noise measured (Std={std_bg}).")
    else:
        feedback.append("Background standard deviation (noise) not found.")

    # 5. SNR/CNR Metrics (40 pts)
    snr_wm = meas.get("snr_wm", 0)
    snr_gm = meas.get("snr_gm", 0)
    cnr = meas.get("cnr", 0)
    
    metrics_score = 0
    if snr_wm > 5: metrics_score += 10
    if snr_gm > 5: metrics_score += 10
    if cnr > 1: metrics_score += 20
    
    score += metrics_score
    if metrics_score > 0:
        feedback.append(f"Metrics found: SNR_WM={snr_wm}, SNR_GM={snr_gm}, CNR={cnr}.")
    else:
        feedback.append("Valid SNR/CNR metrics not found.")

    # Consistency Check (Anti-Gaming)
    # If we have the raw values, calculated SNR should be close to Mean/Std_BG
    if mean_wm > 0 and std_bg > 0 and snr_wm > 0:
        expected_snr = mean_wm / std_bg
        # Allow 10% tolerance for rounding diffs
        if abs(expected_snr - snr_wm) / expected_snr > 0.2:
            feedback.append(f"WARNING: SNR_WM calculation inconsistency (Expected ~{expected_snr:.1f}, Got {snr_wm}).")
            # We don't penalize heavily here as agents might use different formulas, but it's a flag.

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }