#!/usr/bin/env python3
"""
Verifier for synoptic_combine_plot_lecture task.

Verifies that the agent successfully created a Combine Plot (temp+SLP),
a standalone SLP plot, and wrote accurate teaching notes in Panoply.

Scoring Criteria (100 pts total, pass threshold = 75):
  1. Combine plot exported (20 pts)
  2. Standalone SLP plot exported (15 pts)
  3. Teaching notes structurally complete (15 pts)
  4. SLP values physically plausible (25 pts)
  5. VLM Trajectory check confirms workflow (25 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a Panoply visualization task.

The user was tasked with:
1. Opening two datasets in NASA Panoply (air temperature and sea level pressure).
2. Creating a "Combine Plot" (which overlays two variables, e.g., temperature as color fill and pressure as contour lines).
3. Exporting the combined plot and a standalone plot.

Look at the trajectory frames and final screenshot provided. 
1. Did the agent navigate Panoply's interface to open datasets?
2. Did the agent create a map plot that clearly shows BOTH color shading (filled contours) AND line contours overlaid on the same map? (This indicates a successful Combine Plot).

Respond in JSON format:
{
    "panoply_used": true/false,
    "combine_plot_created": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def extract_float(value_str):
    """Extracts a float from a string like '1005 hPa' or '~998'."""
    matches = re.findall(r"[-+]?\d*\.\d+|\d+", str(value_str))
    if matches:
        return float(matches[0])
    return None

def verify_synoptic_combine_plot_lecture(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Extract JSON results
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/synoptic_combine_plot_lecture_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # 1. Combine plot exported (20 pts)
    comb_exists = result.get('combine_plot_exists', False)
    comb_mtime = int(result.get('combine_plot_mtime', 0))
    comb_size = int(result.get('combine_plot_size', 0))

    if comb_exists and comb_mtime >= task_start and comb_size >= 25000:
        score += 20
        feedback.append(f"Combine plot exported successfully ({comb_size} bytes)")
    elif comb_exists and comb_mtime >= task_start and comb_size >= 10000:
        score += 10
        feedback.append(f"Combine plot exported but small ({comb_size} bytes, expected >=25KB)")
    else:
        feedback.append("Combine plot missing or not created during task")

    # 2. Standalone SLP plot exported (15 pts)
    slp_exists = result.get('slp_plot_exists', False)
    slp_mtime = int(result.get('slp_plot_mtime', 0))
    slp_size = int(result.get('slp_plot_size', 0))

    if slp_exists and slp_mtime >= task_start and slp_size >= 15000:
        score += 15
        feedback.append(f"Standalone SLP plot exported successfully ({slp_size} bytes)")
    elif slp_exists and slp_mtime >= task_start and slp_size >= 5000:
        score += 8
        feedback.append(f"Standalone SLP plot exported but small ({slp_size} bytes, expected >=15KB)")
    else:
        feedback.append("Standalone SLP plot missing or not created during task")

    # 3. Teaching notes structurally complete (15 pts)
    notes_exists = result.get('notes_exists', False)
    notes_mtime = int(result.get('notes_mtime', 0))
    
    low_name = result.get('low_pressure_center', '').strip()
    low_val_str = result.get('low_center_slp_hpa', '').strip()
    high_name = result.get('high_pressure_center', '').strip()
    high_val_str = result.get('high_center_slp_hpa', '').strip()

    has_all_fields = bool(low_name) and bool(low_val_str) and bool(high_name) and bool(high_val_str)
    
    if notes_exists and notes_mtime >= task_start and has_all_fields:
        score += 15
        feedback.append("Teaching notes structurally complete")
    elif notes_exists and notes_mtime >= task_start:
        score += 5
        feedback.append("Teaching notes present but missing some required fields")
    else:
        feedback.append("Teaching notes missing or not created during task")

    # 4. SLP values physically plausible (25 pts)
    low_val = extract_float(low_val_str)
    high_val = extract_float(high_val_str)

    if low_val is not None and high_val is not None:
        # Check for un-converted Pascals (e.g. 101300 instead of 1013)
        if low_val > 90000: low_val /= 100.0
        if high_val > 90000: high_val /= 100.0
        
        low_ok = 970 <= low_val <= 1015
        high_ok = 1015 <= high_val <= 1060
        consistent = low_val < high_val
        
        if low_ok and high_ok and consistent:
            score += 25
            feedback.append(f"SLP values physically plausible (Low: {low_val:.1f} hPa, High: {high_val:.1f} hPa)")
        else:
            if not low_ok: feedback.append(f"Reported Low SLP ({low_val:.1f}) is out of typical range")
            if not high_ok: feedback.append(f"Reported High SLP ({high_val:.1f}) is out of typical range")
            if not consistent: feedback.append("Reported Low SLP is greater than or equal to High SLP")
    else:
        feedback.append("Could not parse numeric SLP values from notes")

    # 5. VLM Trajectory Check (25 pts)
    vlm_passed = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(
                    prompt=VLM_PROMPT,
                    images=images
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("panoply_used") and parsed.get("combine_plot_created"):
                        score += 25
                        vlm_passed = True
                        feedback.append("VLM confirms Combine Plot workflow was executed")
                    else:
                        feedback.append(f"VLM verification failed: {parsed.get('reasoning', 'No combine plot detected')}")
                else:
                    feedback.append(f"VLM query failed: {vlm_result.get('error')}")
            else:
                feedback.append("No screenshots available for VLM verification")
        except Exception as e:
            feedback.append(f"VLM verification error: {str(e)}")
    else:
        feedback.append("VLM not available for trajectory verification")

    # Determine Pass/Fail
    key_criteria_met = comb_exists and slp_exists and has_all_fields
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }