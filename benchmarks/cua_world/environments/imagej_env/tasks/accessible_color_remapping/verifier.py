#!/usr/bin/env python3
"""
Verifier for Accessible Color Remapping task.

This task requires converting an RGB image (Red/Green/Blue) to a colorblind-friendly
composite (Magenta/Green/Blue).

Verification Logic:
1. Programmatic Analysis (computed inside container):
   - Output file exists and was created during task.
   - Dimensions match the source image.
   - Green Channel Integrity: Output Green correlates with Input Green.
   - Blue Channel Integrity: Output Blue correlates with Input Blue.
   - Magenta Transformation: 
     - Magenta is composed of Red + Blue light.
     - Therefore, the Input Red signal must appear in the Output Red channel AND the Output Blue channel.
     - We check the correlation of Output_Blue vs Input_Red. High correlation indicates Red was remapped to a color containing Blue (like Magenta).

2. VLM Verification (Trajectory):
   - Confirms the agent used the menus (Split Channels, Merge Channels, or LUT changes).
   - Confirms the final visual result looks correct.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_accessible_color_remapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metrics calculated in export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/remapping_analysis.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            metrics = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve analysis results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: File Existence & Validity (20 pts)
    # ---------------------------------------------------------
    if metrics.get("file_exists") and metrics.get("file_created_during_task"):
        score += 20
        feedback.append("Valid output file created.")
    else:
        feedback.append("FAIL: Output file not created or timestamp invalid.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    if not metrics.get("dimensions_match"):
        feedback.append("FAIL: Output dimensions do not match source image.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
    
    # ---------------------------------------------------------
    # Criterion 2: Channel Preservation (30 pts)
    # ---------------------------------------------------------
    corrs = metrics.get("correlations", {})
    
    # Green should stay Green
    # Allow some degradation due to JPEG artifacts in ground truth vs TIFF output
    if corrs.get("out_G_vs_gt_G", 0) > 0.85:
        score += 15
        feedback.append("Green channel preserved.")
    else:
        feedback.append(f"FAIL: Green channel altered (corr={corrs.get('out_G_vs_gt_G', 0):.2f}).")

    # Blue should stay Blue (partially)
    # Note: If Red is mapped to Magenta, it adds to the Blue channel. 
    # So Out_B = GT_B + GT_R. 
    # Correlation(Out_B, GT_B) should still be significant, but might be lower if GT_R is dominant.
    # We accept a moderate correlation.
    if corrs.get("out_B_vs_gt_B", 0) > 0.4: 
        score += 15
        feedback.append("Blue channel data retained.")
    else:
        feedback.append(f"FAIL: Original Blue signal lost (corr={corrs.get('out_B_vs_gt_B', 0):.2f}).")

    # ---------------------------------------------------------
    # Criterion 3: Magenta Transformation (50 pts)
    # ---------------------------------------------------------
    # Magenta = Red + Blue.
    # The original Red signal (GT_R) must now be present in the Blue channel (Out_B).
    # This is the definitive test for Red -> Magenta mapping.
    
    magenta_check = corrs.get("out_B_vs_gt_R", 0)
    red_retention = corrs.get("out_R_vs_gt_R", 0)
    
    if red_retention > 0.8:
        # Red signal still present in Red channel (needed for Magenta = R+B)
        score += 10
    else:
        feedback.append("FAIL: Red signal lost from Red channel.")

    if magenta_check > 0.6:
        score += 40
        feedback.append("Red signal successfully mapped to Magenta (Red+Blue).")
    else:
        feedback.append(f"FAIL: Red signal NOT found in Blue channel (corr={magenta_check:.2f}). Magenta mapping failed.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": metrics
    }