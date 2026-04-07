#!/usr/bin/env python3
"""
Verifier for african_itcz_latitudinal_profile task.

Scoring criteria (100 pts total, pass threshold = 80):
  1. January profile plot exported (15 pts): itcz_jan_profile.png exists,
     created after task start, size >= 10KB.
  2. July profile plot exported (15 pts): itcz_jul_profile.png exists,
     created after task start, size >= 10KB.
  3. Report formatting (10 pts): Contains the required fields.
  4. Scientific Accuracy - Jan Peak (15 pts): Value parsed correctly between -15.0 and -5.0.
  5. Scientific Accuracy - Jul Peak (15 pts): Value parsed correctly between 5.0 and 15.0.
  6. Scientific Accuracy - Direction (10 pts): Identified as North/Northward.
  7. VLM Trajectory Verification (20 pts): Confirms the agent successfully 
     rendered a 1D line plot during the trajectory, proving they didn't just guess.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_float(s):
    """Safely extract the first floating point number from a string."""
    match = re.search(r'-?\d+\.?\d*', s)
    if match:
        return float(match.group())
    return None

def verify_african_itcz_latitudinal_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    jan_min = metadata.get('jan_peak_min', -15.0)
    jan_max = metadata.get('jan_peak_max', -5.0)
    jul_min = metadata.get('jul_peak_min', 5.0)
    jul_max = metadata.get('jul_peak_max', 15.0)

    # 1. Retrieve Result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/african_itcz_latitudinal_profile_result.json', tmp.name)
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

    # 2. Check File Outputs
    jan_plot_exists = result.get('jan_plot_exists', False)
    jan_plot_mtime = int(result.get('jan_plot_mtime', 0))
    jan_plot_size = int(result.get('jan_plot_size', 0))

    jul_plot_exists = result.get('jul_plot_exists', False)
    jul_plot_mtime = int(result.get('jul_plot_mtime', 0))
    jul_plot_size = int(result.get('jul_plot_size', 0))

    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))

    if jan_plot_exists and jan_plot_mtime >= task_start and jan_plot_size >= 10000:
        score += 15
        feedback.append(f"January profile plot exported ({jan_plot_size} bytes).")
    elif jan_plot_exists and jan_plot_mtime >= task_start:
        score += 7
        feedback.append(f"January profile plot exists but is suspiciously small ({jan_plot_size} bytes).")
    else:
        feedback.append("January profile plot missing or not created during task.")

    if jul_plot_exists and jul_plot_mtime >= task_start and jul_plot_size >= 10000:
        score += 15
        feedback.append(f"July profile plot exported ({jul_plot_size} bytes).")
    elif jul_plot_exists and jul_plot_mtime >= task_start:
        score += 7
        feedback.append(f"July profile plot exists but is suspiciously small ({jul_plot_size} bytes).")
    else:
        feedback.append("July profile plot missing or not created during task.")

    # 3. Check Report and Accuracy
    jan_peak_raw = result.get('jan_peak', '')
    jul_peak_raw = result.get('jul_peak', '')
    direction_raw = result.get('migration_direction', '')

    has_fields = bool(jan_peak_raw) and bool(jul_peak_raw) and bool(direction_raw)
    
    if report_exists and report_mtime >= task_start and has_fields:
        score += 10
        feedback.append("Report successfully created and populated with required fields.")
    else:
        feedback.append("Report missing, outdated, or lacking one or more required fields.")

    # Scientific Accuracy
    jan_peak_val = extract_float(jan_peak_raw)
    if jan_peak_val is not None:
        if jan_min <= jan_peak_val <= jan_max:
            score += 15
            feedback.append(f"January peak ({jan_peak_val}) correctly identified within range [{jan_min}, {jan_max}].")
        else:
            feedback.append(f"January peak ({jan_peak_val}) is outside expected physical range [{jan_min}, {jan_max}].")
    else:
        feedback.append("Could not parse numeric value for January peak.")

    jul_peak_val = extract_float(jul_peak_raw)
    if jul_peak_val is not None:
        if jul_min <= jul_peak_val <= jul_max:
            score += 15
            feedback.append(f"July peak ({jul_peak_val}) correctly identified within range [{jul_min}, {jul_max}].")
        else:
            feedback.append(f"July peak ({jul_peak_val}) is outside expected physical range [{jul_min}, {jul_max}].")
    else:
        feedback.append("Could not parse numeric value for July peak.")

    if 'north' in direction_raw.lower():
        score += 10
        feedback.append("Migration direction correctly identified as North/Northward.")
    else:
        feedback.append(f"Migration direction incorrect or missing. Found: '{direction_raw}'")

    # 4. VLM Trajectory Verification
    # Ensure the agent actually rendered a 1D plot and didn't just guess numbers
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    query_vlm = env_info.get('query_vlm')

    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            if images:
                prompt = """You are evaluating screenshots of a user operating NASA Panoply data visualization software.
                Did the user successfully create and view a '1D Line Plot' on the screen?
                A 1D Line Plot is a standard line graph with X and Y axes showing a single continuous line representing data values.
                It is explicitly NOT a 2D geographical/spatial map of the Earth.
                Respond with JSON containing a single boolean field "1d_plot_visible"."""
                
                vlm_res = query_vlm(images=images, prompt=prompt)
                if vlm_res and vlm_res.get('success') and vlm_res.get('parsed', {}).get('1d_plot_visible', False):
                    score += 20
                    feedback.append("VLM Verification: 1D Line Plot successfully observed in trajectory.")
                else:
                    feedback.append("VLM Verification: No 1D Line Plot observed in trajectory. (Agent likely failed to create it).")
            else:
                feedback.append("VLM Verification: No images available for evaluation.")
        except Exception as e:
            logger.error(f"VLM Verification failed: {e}")
            feedback.append(f"VLM Verification encountered an error: {e}")
    else:
        feedback.append("VLM Verification: query_vlm not available.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }