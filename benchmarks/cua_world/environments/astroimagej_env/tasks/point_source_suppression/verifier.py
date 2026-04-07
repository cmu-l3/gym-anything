#!/usr/bin/env python3
"""
Verifier for Point Source Suppression task.

Verification Strategy:
1. Programmatic Checks (70 points):
   - FITS and TXT files exist and were created during the task (Anti-gaming).
   - FITS analysis: Star count dropped >85% (indicating suppression).
   - FITS analysis: Global median is within 5% of original (indicating nebula structure preserved, not just blacked out).
   - TXT parsing: Original Max, Filtered Max, and Radius are present and reasonable.

2. VLM Checks (30 points):
   - Trajectory verification to ensure AstroImageJ GUI was used (Process > Filters > Median).
   - Output image visually lacks stars but retains nebula features.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logger = logging.getLogger(__name__)

VLM_PROCESS_PROMPT = """You are verifying an agent's completion of an astronomical image processing task using AstroImageJ.

The goal was to remove stars from an image while preserving the nebula using a Median Filter.
Look at these chronological trajectory frames and the final screenshot.

Determine the following:
1. AIJ_GUI_USED: Is there evidence the agent used AstroImageJ's graphical interface? (e.g., loading an image, using menus).
2. MEDIAN_FILTER_ACCESSED: Did the agent access the Median filter dialog (typically via Process > Filters > Median...)? Look for a dialog box asking for "Radius".
3. STARS_REMOVED: In the final image, are the sharp, bright point sources (stars) mostly gone compared to earlier frames?
4. NEBULA_PRESERVED: In the final image, is the large, cloudy, diffuse structure (the nebula / pillars) still visible and not completely blacked out or destroyed?

Respond strictly in JSON format:
{
    "aij_gui_used": true/false,
    "median_filter_accessed": true/false,
    "stars_removed": true/false,
    "nebula_preserved": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_point_source_suppression(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # 1. Read exported result
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # 2. Read ground truth
    gt = {}
    try:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    if gt.get("error"):
        feedback.append(f"Warning: Ground truth error: {gt['error']}")

    orig_median = gt.get("original_median")
    orig_max = gt.get("original_max")
    orig_sources = gt.get("original_sources", 0)

    # Criterion 1: Files Exist & Created During Task (15 pts)
    fits_exists = result.get("fits_exists", False)
    txt_exists = result.get("txt_exists", False)
    created_after = result.get("fits_created_after_start", False) and result.get("txt_created_after_start", False)

    if fits_exists and txt_exists:
        if created_after:
            score += 15
            feedback.append("Output files successfully created during task.")
        else:
            score += 5
            feedback.append("Files exist but may have been created before task started (possible anti-gaming flag).")
    else:
        feedback.append("Missing required FITS or TXT output files.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criterion 2: FITS File Analysis (35 pts)
    filt_median = result.get("filtered_median")
    filt_max = result.get("filtered_max")
    filt_sources = result.get("filtered_sources")

    if filt_median is not None and filt_max is not None and filt_sources is not None:
        # Check source reduction (should drop dramatically if median filter worked)
        source_retention_pct = (filt_sources / max(orig_sources, 1)) * 100
        if source_retention_pct < 15: # 85% drop
            score += 20
            feedback.append(f"Star suppression successful: Point sources reduced by {100-source_retention_pct:.1f}%.")
        elif source_retention_pct < 50:
            score += 10
            feedback.append(f"Partial star suppression: Point sources reduced by {100-source_retention_pct:.1f}%.")
        else:
            feedback.append(f"Star suppression failed: Too many point sources remain ({source_retention_pct:.1f}%).")

        # Check nebula preservation (global median shouldn't change much since stars are small)
        if orig_median is not None and orig_median > 0:
            median_shift_pct = abs(filt_median - orig_median) / orig_median * 100
            if median_shift_pct < 5.0:
                score += 15
                feedback.append(f"Nebula structure preserved: Median shifted by only {median_shift_pct:.2f}%.")
            elif median_shift_pct < 15.0:
                score += 5
                feedback.append(f"Nebula structure somewhat altered: Median shifted by {median_shift_pct:.2f}%.")
            else:
                feedback.append(f"Nebula structure destroyed: Median shifted by {median_shift_pct:.2f}% (Image may be blackened).")
    else:
        feedback.append("FITS analysis failed or data was invalid.")

    # Criterion 3: TXT Stats Parsing (20 pts)
    txt_content = result.get("txt_content", "")
    parsed_orig_max = None
    parsed_filt_max = None
    parsed_radius = None

    # Flexible parsing
    match_orig = re.search(r'(?i)Original_Max\s*[:=]?\s*([0-9.]+)', txt_content)
    if match_orig: parsed_orig_max = float(match_orig.group(1))

    match_filt = re.search(r'(?i)Filtered_Max\s*[:=]?\s*([0-9.]+)', txt_content)
    if match_filt: parsed_filt_max = float(match_filt.group(1))

    match_rad = re.search(r'(?i)Median_Radius_Used\s*[:=]?\s*([0-9.]+)', txt_content)
    if match_rad: parsed_radius = float(match_rad.group(1))

    if parsed_orig_max and orig_max:
        if abs(parsed_orig_max - orig_max) < (0.01 * orig_max) or abs(parsed_orig_max - orig_max) < 100:
            score += 7
            feedback.append("Original Max correctly recorded.")
        else:
            feedback.append(f"Original Max recorded but incorrect ({parsed_orig_max} vs expected {orig_max}).")
    
    if parsed_filt_max and filt_max:
        if abs(parsed_filt_max - filt_max) < (0.05 * filt_max) or abs(parsed_filt_max - filt_max) < 100:
            score += 7
            feedback.append("Filtered Max correctly recorded.")
        else:
            feedback.append(f"Filtered Max recorded but incorrect ({parsed_filt_max} vs actual {filt_max}).")

    if parsed_radius:
        if 2 <= parsed_radius <= 25:
            score += 6
            feedback.append(f"Valid Median Radius recorded: {parsed_radius}")
        else:
            feedback.append(f"Recorded Median Radius seems unreasonable: {parsed_radius}")

    # Criterion 4: VLM Verification (30 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        images = frames + [final_frame] if final_frame else frames
        
        vlm_res = None
        try:
            vlm_raw = query_vlm(prompt=VLM_PROCESS_PROMPT, images=images)
            if vlm_raw and vlm_raw.get("success"):
                vlm_res = vlm_raw.get("parsed", {})
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")

        if vlm_res:
            if vlm_res.get("aij_gui_used", False):
                vlm_score += 10
            if vlm_res.get("median_filter_accessed", False):
                vlm_score += 10
            if vlm_res.get("stars_removed", False) and vlm_res.get("nebula_preserved", False):
                vlm_score += 10
            
            score += vlm_score
            feedback.append(f"VLM Trajectory Verification: {vlm_score}/30 points.")
            feedback.append(f"VLM reasoning: {vlm_res.get('reasoning', 'None')}")
        else:
            feedback.append("VLM verification failed to return valid JSON.")
    else:
        feedback.append("VLM query function not available.")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "score": score,
            "fits_created": created_after,
            "orig_median": orig_median,
            "filt_median": filt_median,
            "orig_sources": orig_sources,
            "filt_sources": filt_sources
        }
    }