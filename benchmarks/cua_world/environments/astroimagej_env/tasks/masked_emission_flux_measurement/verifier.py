#!/usr/bin/env python3
"""
Verifier for Nebula Emission Area and Masked Flux Measurement task.

Scoring Breakdown (100 total):
- 15 points: Image Mean & StdDev accurately extracted from whole image
- 15 points: Threshold correctly calculated (Matches reported Mean + 3*StdDev)
- 15 points: Mask file created (Make Binary output)
- 20 points: Emission Area in square arcsec correctly calculated
- 20 points: Masked Mean Intensity accurately measured
- 15 points: VLM Trajectory shows use of AIJ tools (Threshold/Binary/Measurement)

Pass threshold: 70 points
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent working in AstroImageJ.
The task involves measuring extended emission in an astronomical image.

The expected workflow includes:
1. Opening a FITS image.
2. Taking measurements of the full image.
3. Using the 'Adjust > Threshold' tool (you may see a Threshold dialog box with a histogram).
4. Creating a binary mask (the image turns purely black and white, or Make Binary is selected).
5. Taking measurements of a specific region (you may see an active yellow selection outline / ROI manager, and a Results table with measurements).

Assess if the agent followed this workflow based on the trajectory frames.
Did they use the Threshold/Binary tools and extract measurements?

Respond strictly in JSON format:
{
    "threshold_or_binary_used": true/false,
    "measurements_taken": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def extract_number(content: str, key_patterns: list) -> float:
    """Extract a number from text based on regex patterns."""
    for pattern in key_patterns:
        match = re.search(pattern, content, re.IGNORECASE)
        if match:
            try:
                # Remove commas just in case, handle negative signs
                val_str = match.group(1).replace(',', '')
                return float(val_str)
            except ValueError:
                continue
    return None


def verify_masked_emission_flux(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # 1. Load result JSON
    result = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Load Ground Truth JSON
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/emission_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        feedback.append(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # If GT failed (e.g., astropy missing in env setup), default to some reasonable fallbacks but flag it
    gt_mean = gt.get('image_mean', 13.91)
    gt_std = gt.get('image_stddev', 11.52)
    gt_thresh = gt.get('threshold_value', 48.47)
    gt_area = gt.get('emission_area_sq_arcsec', 555.20)
    gt_masked_mean = gt.get('masked_mean_intensity', 67.89)

    # 3. Parse report content
    report_content = result.get('report_content', '')
    reported_mean = extract_number(report_content, [r'image_mean\s*[=:]\s*([0-9.\-]+)', r'mean[a-z\s]*[=:]\s*([0-9.\-]+)'])
    reported_std = extract_number(report_content, [r'image_stddev\s*[=:]\s*([0-9.\-]+)', r'std[a-z\s]*[=:]\s*([0-9.\-]+)'])
    reported_thresh = extract_number(report_content, [r'threshold_value\s*[=:]\s*([0-9.\-]+)', r'threshold[a-z\s]*[=:]\s*([0-9.\-]+)'])
    reported_area = extract_number(report_content, [r'emission_area_sq_arcsec\s*[=:]\s*([0-9.\-]+)', r'area[a-z\s]*[=:]\s*([0-9.\-]+)'])
    reported_masked_mean = extract_number(report_content, [r'masked_mean_intensity\s*[=:]\s*([0-9.\-]+)', r'masked_mean[a-z\s]*[=:]\s*([0-9.\-]+)'])

    # 4. Evaluate Criteria
    
    # Crit 1: Mean & StdDev (15 pts)
    # Give full points if within 1%, partial if within 5%
    if reported_mean is not None and reported_std is not None:
        mean_err = abs(reported_mean - gt_mean) / abs(gt_mean) if gt_mean != 0 else 1.0
        std_err = abs(reported_std - gt_std) / abs(gt_std) if gt_std != 0 else 1.0
        
        if mean_err <= 0.01 and std_err <= 0.01:
            score += 15
            feedback.append(f"Image Mean & StdDev correct ({reported_mean}, {reported_std})")
        elif mean_err <= 0.05 and std_err <= 0.05:
            score += 7
            feedback.append(f"Image Mean & StdDev approximately correct")
        else:
            feedback.append(f"Image Mean & StdDev incorrect (Expected: ~{gt_mean:.2f}, ~{gt_std:.2f})")
    else:
        feedback.append("Image Mean or StdDev not found in report")

    # Crit 2: Threshold calculation (15 pts)
    # The agent might have used their slightly off mean/std, so we check if their thresh = their mean + 3*their std
    if reported_thresh is not None:
        if reported_mean is not None and reported_std is not None:
            expected_derived_thresh = reported_mean + 3 * reported_std
            if abs(reported_thresh - expected_derived_thresh) < 0.1:
                score += 15
                feedback.append(f"Threshold correctly calculated from reported mean/std: {reported_thresh}")
            elif abs(reported_thresh - gt_thresh) / gt_thresh <= 0.02:
                score += 15
                feedback.append(f"Threshold matches ground truth: {reported_thresh}")
            else:
                feedback.append(f"Threshold incorrect. Expected ~{gt_thresh:.2f}, got {reported_thresh}")
        elif abs(reported_thresh - gt_thresh) / gt_thresh <= 0.02:
            score += 15
            feedback.append(f"Threshold matches ground truth: {reported_thresh}")
        else:
            feedback.append(f"Threshold incorrect")
    else:
        feedback.append("Threshold value not found in report")

    # Crit 3: Mask File Created (15 pts)
    if result.get('mask_file_found') and result.get('mask_file_created_during_task'):
        score += 15
        feedback.append("Binary mask file successfully created and saved")
    elif result.get('mask_file_found'):
        score += 5
        feedback.append("Mask file found, but timestamps suggest it wasn't created during this task")
    else:
        feedback.append("Mask file NOT found")

    # Crit 4: Area Conversion (20 pts)
    # Tolerance 2% to account for threshold rounding
    if reported_area is not None:
        area_err = abs(reported_area - gt_area) / gt_area if gt_area != 0 else 1.0
        if area_err <= 0.02:
            score += 20
            feedback.append(f"Emission Area correctly calculated: {reported_area} sq arcsec")
        elif area_err <= 0.10:
            score += 10
            feedback.append(f"Emission Area roughly correct: {reported_area} sq arcsec (Expected ~{gt_area:.2f})")
        else:
            # Check if they just reported pixels instead of sq arcsec
            pixels = reported_area / 0.01
            pixel_err = abs(pixels - (gt_area / 0.01)) / (gt_area / 0.01) if gt_area != 0 else 1.0
            if pixel_err <= 0.02:
                score += 5
                feedback.append("Emission Area reported in PIXELS instead of square arcsec")
            else:
                feedback.append(f"Emission Area incorrect (Expected ~{gt_area:.2f} sq arcsec)")
    else:
        feedback.append("Emission Area not found in report")

    # Crit 5: Masked Mean Intensity (20 pts)
    if reported_masked_mean is not None:
        masked_mean_err = abs(reported_masked_mean - gt_masked_mean) / gt_masked_mean if gt_masked_mean != 0 else 1.0
        if masked_mean_err <= 0.02:
            score += 20
            feedback.append(f"Masked Mean Intensity correctly measured: {reported_masked_mean}")
        elif masked_mean_err <= 0.05:
            score += 10
            feedback.append(f"Masked Mean Intensity close: {reported_masked_mean}")
        else:
            feedback.append(f"Masked Mean Intensity incorrect (Expected ~{gt_masked_mean:.2f})")
    else:
        feedback.append("Masked Mean Intensity not found in report")

    # Crit 6: VLM Trajectory Verification (15 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("threshold_or_binary_used"):
                score += 10
                feedback.append("VLM: Threshold/Binary workflow observed")
            else:
                feedback.append("VLM: Threshold/Binary workflow not clearly observed")
                
            if parsed.get("measurements_taken"):
                score += 5
                feedback.append("VLM: Measurement workflow observed")
        else:
            feedback.append("VLM verification failed to process")
    else:
        feedback.append("VLM query unavailable for trajectory validation")

    # Final logic
    key_criteria_met = result.get('mask_file_found') and (reported_area is not None or reported_masked_mean is not None)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }