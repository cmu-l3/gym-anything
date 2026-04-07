#!/usr/bin/env python3
"""
Verifier for Binary Source Masking task.

Scoring (100 points total):
  Criterion 1: File Existence & FITS Format (15 pts) - Also checks if created during task
  Criterion 2: Dimensionality Match (15 pts)
  Criterion 3: Strict Binary Output (25 pts)
  Criterion 4: Accurate Source Alignment (25 pts)
  Criterion 5: Morphological Dilation (20 pts)
  
Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent performing image processing in AstroImageJ.
The task was to open a FITS image, apply a Threshold, convert it to a Binary mask, and use the Dilate tool.

Analyze the progression and determine:
1. Did the agent use AstroImageJ?
2. Is there evidence of the agent opening or using the Threshold tool (e.g., Image > Adjust > Threshold dialog, red overlay on bright stars)?
3. Is there evidence of the agent making the image binary or using the Dilate tool (e.g., Process > Binary menus, black and white image)?

Respond in JSON format:
{
    "used_astroimagej": true/false,
    "used_threshold": true/false,
    "used_binary_dilate": true/false,
    "confidence": "low/medium/high",
    "observations": "brief explanation"
}
"""

def verify_create_binary_source_mask(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Retrieve programmatic results
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    if result.get("error"):
        feedback.append(f"Analysis script error: {result['error']}")

    # 2. VLM Trajectory Check (Anti-gaming & Workflow validation)
    query_vlm = env_info.get('query_vlm')
    frames = sample_trajectory_frames(traj, n=5)
    used_aij = True

    if query_vlm and frames:
        try:
            vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                used_aij = parsed.get("used_astroimagej", True)
                if parsed.get("used_threshold"):
                    feedback.append("VLM confirmed Threshold usage.")
                if parsed.get("used_binary_dilate"):
                    feedback.append("VLM confirmed Binary/Dilate usage.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")

    if not used_aij:
        return {
            "passed": False,
            "score": 0,
            "feedback": "VLM found no evidence of AstroImageJ usage. Task failed due to possible gaming."
        }

    # Criterion 1: File Existence & FITS Format (15 pts)
    mask_exists = result.get("mask_exists", False)
    valid_fits = result.get("valid_fits", False)
    created_during = result.get("file_created_during_task", False)
    
    if mask_exists and valid_fits:
        if created_during:
            score += 15
            feedback.append("Output is a valid FITS file and was created during the task (+15)")
        else:
            score += 7
            feedback.append("Output is a valid FITS file but existed before task (+7)")
    elif mask_exists:
        feedback.append("Output exists but is not a valid FITS file (+0)")
    else:
        feedback.append("Output file does not exist (+0)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 2: Dimensionality Match (15 pts)
    if result.get("dim_match", False):
        score += 15
        feedback.append("Mask dimensions match the original image (+15)")
    else:
        feedback.append("Mask dimensions DO NOT match the original image (+0)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 3: Strict Binary Output (25 pts)
    if result.get("is_binary", False):
        score += 25
        feedback.append("Image is strictly binary (exactly 2 unique values) (+25)")
    else:
        unique_vals = result.get("unique_vals", 0)
        feedback.append(f"Image is NOT strictly binary (found {unique_vals} unique values) (+0)")
        
    # Criterion 4: Accurate Source Alignment (25 pts)
    if result.get("alignment_valid", False):
        source_m = result.get("source_mean", 0)
        bg_m = result.get("bg_mean", 0)
        score += 25
        feedback.append(f"Source alignment valid (Source mean: {source_m:.1f} > BG mean: {bg_m:.1f}) (+25)")
    else:
        feedback.append("Source alignment INVALID (Mask does not isolate bright pixels) (+0)")

    # Criterion 5: Morphological Dilation (20 pts)
    if result.get("dilation_valid", False):
        score += 20
        feedback.append(f"Morphological dilation confirmed (Source area: {result.get('source_area')} > Baseline: {result.get('baseline_area')}) (+20)")
    else:
        feedback.append(f"Morphological dilation NOT confirmed (Source area: {result.get('source_area')} vs Baseline: {result.get('baseline_area')}) (+0)")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }