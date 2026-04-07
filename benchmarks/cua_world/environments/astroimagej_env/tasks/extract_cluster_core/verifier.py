#!/usr/bin/env python3
"""
Verifier for the Extract Globular Cluster Core Subframe task.

Verification Strategy:
1. Valid Subframe File (20 pts): Output FITS exists and was created during task.
2. Accurate Dimensions (20 pts): Cropped image is ~300x300 pixels.
3. Subframe Accuracy (15 pts): Mean intensity matches the expected core region (within 20%).
4. Report Existence (10 pts): Report file created during task.
5. Report Stats - Full Image (10 pts): Full image mean intensity accurately reported.
6. Report Stats - Subframe (10 pts): Subframe mean accurately reported.
7. Core Concentration Ratio (10 pts): Subframe-to-Full ratio reported accurately.
8. VLM Trajectory Check (5 pts): Visual evidence of ROI drawing and image cropping.
"""

import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_numbers(text):
    """Extract all valid integers and floats from a string."""
    return [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", text)]

def verify_extract_cluster_core(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Load exported results
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Load Ground Truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/extraction_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # --- Criteria 1: Valid Subframe File (20 pts) ---
    fits_ok = False
    if result.get("fits_exists") and result.get("fits_created_during_task"):
        if result.get("sub_shape") is not None:
            score += 20
            fits_ok = True
            feedback_parts.append("Valid FITS created during task")
        else:
            feedback_parts.append("FITS file created but invalid/corrupted")
    else:
        feedback_parts.append("FITS output missing or not created during task")

    # --- Criteria 2: Accurate Dimensions (20 pts) ---
    shape = result.get("sub_shape")
    if shape and len(shape) >= 2:
        h, w = shape[0], shape[1]
        # Accept anything within 300x300 +/- 30px to account for manual UI drag inaccuracies
        if 270 <= h <= 330 and 270 <= w <= 330:
            score += 20
            feedback_parts.append(f"Subframe dimensions accurate ({h}x{w})")
        else:
            feedback_parts.append(f"Subframe dimensions incorrect (expected ~300x300, got {h}x{w})")

    # --- Criteria 3: Subframe Accuracy / Mean Intensity (15 pts) ---
    sub_mean = result.get("sub_mean")
    gt_sub_mean = gt.get("sub_mean", 1.0)
    if sub_mean is not None:
        # Check if mean matches ground truth core mean within 20%
        if abs(sub_mean - gt_sub_mean) / gt_sub_mean < 0.20:
            score += 15
            feedback_parts.append("Subframe intensity matches expected core region")
        else:
            feedback_parts.append(f"Subframe intensity incorrect (wrong location extracted)")
    
    # --- Criteria 4: Report Existence (10 pts) ---
    report_content = result.get("report_content", "")
    if result.get("report_exists") and result.get("report_created_during_task"):
        score += 10
        feedback_parts.append("Report file created")
    else:
        feedback_parts.append("Report file missing")

    # Extract numbers from report for validation
    numbers_in_report = extract_numbers(report_content)
    
    # --- Criteria 5: Report Stats - Full Image (10 pts) ---
    gt_full_mean = gt.get("full_mean", 1.0)
    full_mean_found = any(abs(n - gt_full_mean) / gt_full_mean < 0.05 for n in numbers_in_report)
    if full_mean_found:
        score += 10
        feedback_parts.append("Full image mean accurately reported")
    else:
        feedback_parts.append("Full image mean missing or inaccurate in report")

    # --- Criteria 6: Report Stats - Subframe (10 pts) ---
    sub_mean_found = any(abs(n - gt_sub_mean) / gt_sub_mean < 0.05 for n in numbers_in_report)
    if sub_mean_found:
        score += 10
        feedback_parts.append("Subframe mean accurately reported")
    else:
        feedback_parts.append("Subframe mean missing or inaccurate in report")

    # --- Criteria 7: Core Concentration Ratio (10 pts) ---
    gt_ratio = gt_sub_mean / gt_full_mean if gt_full_mean else 1.0
    ratio_found = any(abs(n - gt_ratio) / gt_ratio < 0.05 for n in numbers_in_report)
    if ratio_found:
        score += 10
        feedback_parts.append("Core concentration ratio accurately reported")
    else:
        feedback_parts.append("Core concentration ratio missing or inaccurate")

    # --- Criteria 8: VLM Trajectory Check (5 pts) ---
    # Sample trajectory frames
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze this chronological sequence of screenshots from a user interacting with AstroImageJ.
Did the user draw a rectangular selection box (ROI) on an astronomical image and perform a crop/duplicate operation resulting in a new, smaller image window?

Look for:
1. The main image with a yellow or colored rectangular outline drawn on it.
2. A new, significantly smaller image window appearing later in the sequence containing the extracted region.

Reply in JSON:
{
    "roi_drawn": true/false,
    "crop_performed": true/false
}
"""
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("roi_drawn") and parsed.get("crop_performed"):
                    score += 5
                    feedback_parts.append("VLM confirmed visual ROI/crop operations")
                else:
                    feedback_parts.append("VLM did not detect ROI/crop visual confirmation")

    # Evaluate final pass/fail
    passed = score >= 60 and fits_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }