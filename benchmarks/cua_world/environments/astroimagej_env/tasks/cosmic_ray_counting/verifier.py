#!/usr/bin/env python3
"""
Verifier for Cosmic Ray Event Detection and Counting.

Hybrid verification (programmatic file checking + VLM trajectory analysis).

Scoring (100 points total):
  Programmatic Checks (70 points):
  - Difference image exists and is valid (10 pts)
  - Report exists with EXPTIME and dimensions (10 pts)
  - Reported difference statistics match GT within 20% (15 pts)
  - Cosmic ray count within 40% of GT (15 pts)
  - Hit rate within 50% of GT (20 pts)
  
  VLM Checks (30 points):
  - Agent actually loaded FITS, used Image Calculator, and viewed results.

Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)

# VLM Prompt to check trajectory progression
TRAJECTORY_PROMPT = """You are evaluating an agent performing astronomical image arithmetic in AstroImageJ.
The goal was to open two FITS dark frames, subtract them to create a difference image, and measure statistics to find cosmic rays.

Look at these chronologically sampled screenshots and assess:
1. IMAGES_LOADED: Are two grayscale FITS images visible at any point?
2. IMAGE_CALCULATOR_USED: Is the "Image Calculator" dialog box visible at any point, or is there an image titled something like "Result of..." or "Difference"?
3. ANALYSIS_PERFORMED: Is there evidence of measurement (e.g., a Histogram window, a Results table, or the Find Maxima dialog)?

Respond strictly in JSON format:
{
    "images_loaded": true/false,
    "image_calculator_used": true/false,
    "analysis_performed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def extract_number(text, patterns):
    """Attempt to extract a float number from text using multiple regex patterns."""
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            try:
                # Remove commas in numbers (e.g., 1,000)
                val_str = match.group(1).replace(',', '')
                return float(val_str)
            except ValueError:
                pass
    return None

def verify_cosmic_ray_counting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # 1. Load result JSON
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # 2. Load ground truth JSON
    gt = {}
    try:
        gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/cosmic_ray_ground_truth.json", gt_temp.name)
        with open(gt_temp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Ground truth file error: {e}"}
    finally:
        if os.path.exists(gt_temp.name):
            os.unlink(gt_temp.name)

    # Extract GT values
    gt_exptime = gt.get('exptime', 0)
    gt_median = gt.get('diff_median', 0)
    gt_std = gt.get('diff_std', 0)
    gt_count = gt.get('num_events', 0)
    gt_rate = gt.get('hit_rate', 0)
    gt_raw_mean = gt.get('raw_dark_mean', 1000)

    # Criterion 1: Difference Image (10 points)
    if result.get('diff_image_exists'):
        if not result.get('diff_image_created_during_task'):
            feedback.append("Difference image exists but was not created during task (anti-gaming).")
        else:
            stats = result.get('diff_image_stats', {})
            diff_mean = stats.get('mean', float('inf'))
            
            # Anti-gaming: Ensure they didn't just copy the raw dark. 
            # A raw dark has a high bias level (~1000+), while |dark1-dark2| is centered near 0.
            if diff_mean < (gt_raw_mean * 0.5):
                score += 10
                feedback.append("Difference image saved and appears valid (mean is near zero).")
            else:
                score += 3
                feedback.append(f"Difference image saved but mean ({diff_mean:.1f}) is too high. Did you subtract?")
    else:
        feedback.append("Difference image not found.")

    # Parse Report
    report_text = result.get('report_content', '')
    
    rep_exptime = extract_number(report_text, [r'exposure.*?(?:time)?.*?[:=]\s*([0-9.]+)', r'([0-9.]+)\s*s(?:ec|econds)?'])
    rep_median = extract_number(report_text, [r'median.*?[:=]\s*([0-9.]+)', r'med.*?[:=]\s*([0-9.]+)'])
    rep_std = extract_number(report_text, [r'(?:standard\s*deviation|std\s*dev|std|sigma).*?[:=]\s*([0-9.]+)'])
    rep_count = extract_number(report_text, [r'(?:count|events|number|detected).*?[:=]\s*([0-9]+)'])
    rep_rate = extract_number(report_text, [r'rate.*?[:=]\s*([0-9.]+(?:e-[0-9]+)?)', r'events/pixel/second.*?[:=]\s*([0-9.]+(?:e-[0-9]+)?)'])

    # Criterion 2: Report Exists & Basic Metadata (10 points)
    if result.get('report_exists'):
        if not result.get('report_created_during_task'):
            feedback.append("Report file existed before task began.")
        else:
            if rep_exptime is not None and abs(rep_exptime - gt_exptime) < 1.0:
                score += 10
                feedback.append(f"Report found with correct exposure time ({rep_exptime}s).")
            else:
                score += 5
                feedback.append(f"Report found, but missing or incorrect exposure time (found {rep_exptime}).")
    else:
        feedback.append("Report file not found.")

    # Criterion 3: Difference Stats (15 points)
    if rep_median is not None and rep_std is not None:
        med_err = abs(rep_median - gt_median) / max(gt_median, 1)
        std_err = abs(rep_std - gt_std) / max(gt_std, 1)
        
        if med_err < 0.20 and std_err < 0.20:
            score += 15
            feedback.append("Reported median and std dev match ground truth closely.")
        elif med_err < 0.50 and std_err < 0.50:
            score += 8
            feedback.append("Reported median/std dev are approximately correct.")
        else:
            feedback.append("Reported statistics deviate significantly from expected.")
    else:
        feedback.append("Could not parse median or standard deviation from report.")

    # Criterion 4: Cosmic Ray Count (15 points)
    if rep_count is not None:
        count_err = abs(rep_count - gt_count) / max(gt_count, 1)
        if count_err < 0.40:
            score += 15
            feedback.append(f"Cosmic ray count ({rep_count}) within tolerance (GT ~{gt_count}).")
        elif count_err < 0.80:
            score += 7
            feedback.append(f"Cosmic ray count ({rep_count}) is somewhat inaccurate (GT ~{gt_count}).")
        else:
            feedback.append(f"Cosmic ray count ({rep_count}) is far from expected (~{gt_count}).")
    else:
        feedback.append("Could not parse cosmic ray count from report.")

    # Criterion 5: Hit Rate (20 points)
    if rep_rate is not None:
        rate_err = abs(rep_rate - gt_rate) / max(gt_rate, 1e-9)
        if rate_err < 0.50:
            score += 20
            feedback.append(f"Hit rate ({rep_rate:e}) matches ground truth within tolerance.")
        elif rate_err < 1.0:
            score += 10
            feedback.append(f"Hit rate ({rep_rate:e}) is of the right order of magnitude.")
        else:
            feedback.append(f"Hit rate ({rep_rate:e}) is incorrect (GT ~{gt_rate:e}).")
    else:
        feedback.append("Could not parse hit rate from report.")

    # Criterion 6: VLM Trajectory Verification (30 points)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            try:
                vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    
                    if parsed.get("images_loaded"):
                        vlm_score += 10
                        feedback.append("VLM: FITS images loaded.")
                    if parsed.get("image_calculator_used"):
                        vlm_score += 10
                        feedback.append("VLM: Image arithmetic evident.")
                    if parsed.get("analysis_performed"):
                        vlm_score += 10
                        feedback.append("VLM: Measurement analysis evident.")
                else:
                    feedback.append("VLM verification query failed.")
            except Exception as e:
                feedback.append(f"VLM verification error: {e}")
        else:
            feedback.append("No trajectory frames available for VLM.")
    else:
        feedback.append("VLM querying unavailable.")

    score += vlm_score

    # Determine Pass/Fail
    passed = score >= 60 and (result.get('diff_image_exists') or result.get('report_exists'))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "gt_median": gt_median,
            "gt_std": gt_std,
            "gt_count": gt_count,
            "gt_rate": gt_rate,
            "rep_median": rep_median,
            "rep_std": rep_std,
            "rep_count": rep_count,
            "rep_rate": rep_rate
        }
    }