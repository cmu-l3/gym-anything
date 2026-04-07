#!/usr/bin/env python3
"""
Verifier for UV Star-Forming Region Census task.

Verification Strategy:
1. Parse the agent's report file (`uv_knots_report.txt`).
2. Compare the extracted values to the dynamically generated Ground Truth.
3. VLM Check on Trajectory: Ensure the agent used the AstroImageJ GUI
   (drawing ROI, interacting with Gaussian Blur/Threshold/Analyze Particles)
   to deter script-based gaming without GUI interaction.
"""

import os
import re
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to ensure genuine GUI progression
TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent performing image analysis in AstroImageJ.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful completion of the workflow, the agent should:
1. Load the FITS image (uit_galaxy.fits) showing a galaxy.
2. Draw a small square region of interest (ROI) in the top-left corner.
3. Open a Threshold dialog, or Gaussian Blur dialog, or Analyze Particles dialog.
4. Generate a Results table showing particle areas and counts.

Assess:
1. WORKFLOW_COMPLETED: Did the agent use the GUI to perform the analysis?
2. ROI_VISIBLE: At any point, is a square selection (ROI box) visible in the top left?
3. DIALOGS_VISIBLE: At any point, are analysis dialogs (Threshold, Gaussian Blur, or Analyze Particles) visible?
4. MEANINGFUL_PROGRESSION: Do the frames show real GUI state changes that progress towards the goal?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "roi_visible": true/false,
    "dialogs_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression you see across the frames"
}
"""

def _vlm_query(query_vlm, prompt, images=None):
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

def verify_uv_census(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # 1. Load result.json
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Load ground_truth.json
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/uv_census_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Ground truth file error: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    expected_bg_mean = gt.get("bg_mean", 0)
    expected_bg_std = gt.get("bg_std", 0)
    expected_thresh = gt.get("threshold", 0)
    expected_knots = gt.get("total_knots", 0)
    expected_area = gt.get("total_area", 0)

    # 3. Check report file
    if not result.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file 'uv_knots_report.txt' does not exist."}
    
    if not result.get("file_created_during_task"):
        feedback.append("WARNING: Report file appears to be created before task started (gaming attempt?).")

    content = result.get("report_content", "")
    
    # Extract values via regex
    bg_mean, bg_std, calc_thresh, total_knots, total_area = None, None, None, None, None

    m = re.search(r'Background_Mean:\s*([0-9.]+)', content, re.IGNORECASE)
    if m: bg_mean = float(m.group(1))

    m = re.search(r'Background_StdDev:\s*([0-9.]+)', content, re.IGNORECASE)
    if m: bg_std = float(m.group(1))

    m = re.search(r'Calculated_Threshold:\s*([0-9.]+)', content, re.IGNORECASE)
    if m: calc_thresh = float(m.group(1))

    m = re.search(r'Total_Knots:\s*([0-9]+)', content, re.IGNORECASE)
    if m: total_knots = int(m.group(1))

    m = re.search(r'Total_Area:\s*([0-9.]+)', content, re.IGNORECASE)
    if m: total_area = float(m.group(1))

    if all(v is not None for v in [bg_mean, bg_std, calc_thresh, total_knots, total_area]):
        score += 10
        feedback.append("Report file format correct.")
    else:
        feedback.append("Report file missing required keys or malformed.")

    # Scoring Criteria
    
    # Background Mean (15 points) - 5% tolerance
    if bg_mean is not None:
        if abs(bg_mean - expected_bg_mean) / max(expected_bg_mean, 1e-5) <= 0.05:
            score += 15
            feedback.append(f"Background mean correct ({bg_mean})")
        else:
            feedback.append(f"Background mean incorrect ({bg_mean} vs expected {expected_bg_mean:.2f})")

    # Background StdDev (15 points) - 10% tolerance
    if bg_std is not None:
        if abs(bg_std - expected_bg_std) / max(expected_bg_std, 1e-5) <= 0.10:
            score += 15
            feedback.append(f"Background stddev correct ({bg_std})")
        else:
            feedback.append(f"Background stddev incorrect ({bg_std} vs expected {expected_bg_std:.2f})")

    # Calculated Threshold (10 points)
    if calc_thresh is not None and bg_mean is not None and bg_std is not None:
        expected_calc = bg_mean + 3 * bg_std
        if abs(calc_thresh - expected_calc) <= 0.05:
            score += 10
            feedback.append(f"Calculated threshold correct ({calc_thresh})")
        else:
            feedback.append(f"Calculated threshold incorrect ({calc_thresh} vs computed {expected_calc:.2f})")

    # Total Knots (25 points) - 10% tolerance or ±5 absolute
    if total_knots is not None:
        err = abs(total_knots - expected_knots)
        if err <= 5 or (expected_knots > 0 and err / expected_knots <= 0.10):
            score += 25
            feedback.append(f"Total knots correct ({total_knots})")
        elif err <= 15 or (expected_knots > 0 and err / expected_knots <= 0.25):
            score += 12
            feedback.append(f"Total knots approximate ({total_knots} vs expected {expected_knots})")
        else:
            feedback.append(f"Total knots incorrect ({total_knots} vs expected {expected_knots})")

    # Total Area (25 points) - 15% tolerance
    if total_area is not None:
        if expected_area > 0:
            err = abs(total_area - expected_area) / expected_area
            if err <= 0.15:
                score += 25
                feedback.append(f"Total area correct ({total_area})")
            elif err <= 0.30:
                score += 12
                feedback.append(f"Total area approximate ({total_area} vs expected {expected_area})")
            else:
                feedback.append(f"Total area incorrect ({total_area} vs expected {expected_area})")

    # VLM Trajectory Check
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
        if vlm_res:
            if not vlm_res.get("meaningful_progression", False):
                feedback.append("VLM Penalty: No meaningful GUI progression observed. Score halved.")
                score = score // 2
            else:
                feedback.append("VLM Check: Meaningful GUI progression observed.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }