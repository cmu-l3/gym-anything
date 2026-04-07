#!/usr/bin/env python3
"""
Verifier for Flat Field Noise Analysis task.

Scoring (100 points total):
  1. Median projection valid & accurate (15 pts)
  2. Std Dev projection valid & accurate (15 pts)
  3. Measured signals within 30% of GT (15 pts)
  4. Measured gain within 40% of GT (20 pts)
  5. Bad pixels count within factor of 3 of GT (10 pts)
  6. Results text file completeness (10 pts)
  7. VLM Trajectory Verification showing Z-projection tools (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a desktop interaction involving AstroImageJ.
The user's goal was to perform flat field noise analysis by:
1. Loading an image sequence/stack of flats.
2. Generating a Z-projection (Median).
3. Generating a Z-projection (Standard Deviation).
4. Measuring regions.

Look at these sampled trajectory screenshots and assess:
1. IS_STACK_LOADED: Is there evidence of a multi-image stack loaded? (Look for a window with a slider at the bottom, or 'stack' in title).
2. Z_PROJECTION_USED: Is there evidence of Z-projection being used? (A dialog box for 'ZProjection', 'Median', or 'Standard Deviation').
3. MEASUREMENT_SHOWN: Are there any measurement/results windows or bounding boxes drawn on the images?

Respond with a JSON object:
{
    "is_stack_loaded": true/false,
    "z_projection_used": true/false,
    "measurement_shown": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_noise_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load Result
    result = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # Load Ground Truth
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/flat_noise_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    score = 0
    feedback = []

    # 1 & 2. FITS Projections (15 + 15 = 30 pts)
    med_stats = result.get("median_stats")
    std_stats = result.get("stddev_stats")
    
    gt_shape = gt.get("shape", [])
    gt_med_mean = gt.get("med_mean", 0)
    gt_std_mean = gt.get("std_mean", 0)

    # Median Check
    if med_stats and "error" not in med_stats:
        if med_stats.get("created_during_task", False):
            if med_stats.get("shape") == gt_shape:
                mean_diff = abs(med_stats.get("mean", 0) - gt_med_mean)
                if mean_diff < (gt_med_mean * 0.1):  # Within 10%
                    score += 15
                    feedback.append("✅ Valid median projection created.")
                else:
                    score += 5
                    feedback.append(f"⚠️ Median projection has unexpected mean ({med_stats.get('mean'):.1f} vs expected {gt_med_mean:.1f}).")
            else:
                feedback.append("❌ Median projection shape mismatch.")
        else:
            feedback.append("❌ Median file exists but was not created during task.")
    else:
        feedback.append("❌ Median projection missing or invalid.")

    # Stddev Check
    if std_stats and "error" not in std_stats:
        if std_stats.get("created_during_task", False):
            if std_stats.get("shape") == gt_shape:
                mean_diff = abs(std_stats.get("mean", 0) - gt_std_mean)
                if mean_diff < (gt_std_mean * 0.2):  # Within 20%
                    score += 15
                    feedback.append("✅ Valid stddev projection created.")
                else:
                    score += 5
                    feedback.append(f"⚠️ Stddev projection has unexpected mean ({std_stats.get('mean'):.1f} vs expected {gt_std_mean:.1f}).")
            else:
                feedback.append("❌ Stddev projection shape mismatch.")
        else:
            feedback.append("❌ Stddev file exists but was not created during task.")
    else:
        feedback.append("❌ Stddev projection missing or invalid.")

    # Parse Text
    parsed = result.get("parsed_text", {})
    
    # 3. Measured Signals (15 pts)
    signals = parsed.get("signals", [])
    gt_signals = gt.get("signals", [])
    if len(signals) >= 4 and len(gt_signals) >= 4:
        # Check if average signal is within 30% of average GT signal
        avg_sig = sum(signals[:4]) / 4.0
        avg_gt_sig = sum(gt_signals[:4]) / 4.0
        if abs(avg_sig - avg_gt_sig) < (avg_gt_sig * 0.3):
            score += 15
            feedback.append("✅ Measured signals are accurate.")
        else:
            score += 5
            feedback.append(f"⚠️ Measured signals differ significantly from GT (avg {avg_sig:.1f} vs {avg_gt_sig:.1f}).")
    else:
        feedback.append("❌ Quadrant signals missing from text file.")

    # 4. Measured Gain (20 pts)
    gain = parsed.get("gain")
    gt_gain = gt.get("mean_gain", 1.0)
    if gain is not None:
        if abs(gain - gt_gain) < (gt_gain * 0.4):
            score += 20
            feedback.append(f"✅ Gain estimate accurate ({gain} e-/ADU).")
        elif abs(gain - gt_gain) < (gt_gain * 1.0):
            score += 10
            feedback.append(f"⚠️ Gain estimate somewhat inaccurate ({gain} vs {gt_gain:.2f} e-/ADU).")
        else:
            feedback.append(f"❌ Gain estimate wildly inaccurate ({gain} vs {gt_gain:.2f} e-/ADU).")
    else:
        feedback.append("❌ Gain estimate missing from text file.")

    # 5. Bad Pixels (10 pts)
    bad_pixels = parsed.get("bad_pixels")
    gt_bad_pixels = gt.get("bad_pixel_count", 0)
    if bad_pixels is not None:
        if gt_bad_pixels == 0 and bad_pixels < 50:
            score += 10
            feedback.append("✅ Bad pixel count accurate.")
        elif gt_bad_pixels > 0 and (gt_bad_pixels / 3.0) <= bad_pixels <= (gt_bad_pixels * 3.0):
            score += 10
            feedback.append("✅ Bad pixel count accurate.")
        else:
            score += 3
            feedback.append(f"⚠️ Bad pixel count inaccurate ({bad_pixels} vs ~{gt_bad_pixels}).")
    else:
        feedback.append("❌ Bad pixel count missing.")

    # 6. Text File Completeness (10 pts)
    if result.get("text_file_exists"):
        if parsed.get("poisson_check") in ["PASS", "FAIL"]:
            score += 10
            feedback.append("✅ Text file formatting and content complete.")
        else:
            score += 5
            feedback.append("⚠️ Text file exists but missing PASS/FAIL flag.")
    else:
        feedback.append("❌ noise_analysis.txt missing.")

    # 7. VLM Trajectory Verification (15 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res.get("success"):
                vlm_parsed = vlm_res.get("parsed", {})
                if vlm_parsed.get("is_stack_loaded") and vlm_parsed.get("z_projection_used"):
                    score += 15
                    feedback.append("✅ VLM confirmed stack loading and Z-projection usage.")
                elif vlm_parsed.get("z_projection_used"):
                    score += 10
                    feedback.append("⚠️ VLM confirmed Z-projection but stack loading unclear.")
                else:
                    feedback.append("❌ VLM did not detect Z-projection operations in screenshots.")
            else:
                feedback.append("⚠️ VLM query failed.")

    key_criteria_met = (result.get("median_file_exists") and result.get("text_file_exists"))
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }