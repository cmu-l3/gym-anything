#!/usr/bin/env python3
"""
Verifier for satellite_rf_rain_fade_analysis task.

Occupation: Satellite Communications Engineer / RF Systems Engineer
Industry: Aerospace / Telecommunications
Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Plot Export (15 pts): jakarta_precip_timeseries.png exists, >= 10KB, created after start.
  2. Report Formatting (15 pts): rf_fade_margin_report.txt exists and has all 5 keys.
  3. Location Accuracy (15 pts): GRID_LATITUDE and GRID_LONGITUDE within valid range for Jakarta.
  4. Peak Month Accuracy (15 pts): PEAK_RAIN_MONTH correctly identified as January (Jan).
  5. Peak Value Accuracy (15 pts): PEAK_PRATE_VALUE is within valid NCEP range (~8e-5 to 2.5e-4).
  6. VLM Trajectory Verification (25 pts): Agent actively used Panoply and created a 1D Line Plot.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if an AI agent successfully used NASA Panoply to create a 1D Time-Series Line Plot.
Look at the sequence of screenshots from the agent's workflow.

Did the agent successfully create a 1D Line Plot (a graph with a single line tracking values over time) in Panoply?
Standard 2D color maps of the globe DO NOT count as 1D line plots. 

Respond with a JSON object containing:
{
    "created_1d_line_plot": true/false,
    "reasoning": "Brief explanation of what is visible in the frames"
}
"""

def verify_satellite_rf_rain_fade_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/satellite_rf_rain_fade_analysis_result.json', tmp.name)
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

    # ----------------------------------------------------------------
    # Criterion 1: Plot Export (15 pts)
    # ----------------------------------------------------------------
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 10000:
        score += 15
        feedback.append(f"1D Plot exported correctly ({plot_size} bytes)")
    elif plot_exists and plot_mtime >= task_start:
        score += 7
        feedback.append(f"1D Plot exported but file is suspiciously small ({plot_size} bytes)")
    else:
        feedback.append("1D Plot missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 2: Report Formatting (15 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    loc = result.get('gateway_location', '').strip()
    lat_raw = result.get('grid_latitude', '').strip()
    lon_raw = result.get('grid_longitude', '').strip()
    month_raw = result.get('peak_rain_month', '').strip()
    val_raw = result.get('peak_prate_value', '').strip()

    has_all_keys = bool(loc and lat_raw and lon_raw and month_raw and val_raw)

    if report_exists and report_mtime >= task_start and has_all_keys:
        score += 15
        feedback.append("Report formatted correctly with all keys")
    elif report_exists and report_mtime >= task_start:
        score += 7
        feedback.append("Report exists but is missing required keys")
    else:
        feedback.append("Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 3: Location Accuracy (15 pts)
    # Target: Jakarta (~6 S, 106 E). NCEP Grid: [-8.0 to -4.0], [104.0 to 108.0]
    # ----------------------------------------------------------------
    lat_valid = False
    lon_valid = False
    try:
        lat = float(lat_raw.replace('S', '').replace('N', '').strip())
        # if they wrote '6 S', float fails. Let's do a basic catch:
        if 'S' in lat_raw.upper() and lat > 0:
            lat = -lat
            
        lon = float(lon_raw.replace('E', '').replace('W', '').strip())
        
        if -8.0 <= lat <= -4.0:
            lat_valid = True
        if 104.0 <= lon <= 108.0:
            lon_valid = True
            
        if lat_valid and lon_valid:
            score += 15
            feedback.append(f"Grid coordinates ({lat}, {lon}) correctly match Jakarta region")
        else:
            feedback.append(f"Grid coordinates ({lat}, {lon}) outside expected Jakarta bounds")
    except ValueError:
        feedback.append(f"Could not parse grid coordinates: Lat '{lat_raw}', Lon '{lon_raw}'")

    # ----------------------------------------------------------------
    # Criterion 4: Peak Month (15 pts)
    # ----------------------------------------------------------------
    if month_raw.lower() in ['january', 'jan', '01', '1']:
        score += 15
        feedback.append(f"Peak month correctly identified as {month_raw}")
    elif month_raw:
        feedback.append(f"Incorrect peak month: {month_raw} (Expected January)")

    # ----------------------------------------------------------------
    # Criterion 5: Peak Value Accuracy (15 pts)
    # Range: 0.00008 to 0.00025 kg/m^2/s
    # ----------------------------------------------------------------
    try:
        val = float(val_raw)
        if 0.00008 <= val <= 0.00025:
            score += 15
            feedback.append(f"Peak precipitation value ({val}) is geophysically accurate")
        else:
            feedback.append(f"Peak precipitation value ({val}) is outside expected NCEP climatological range")
    except ValueError:
        feedback.append(f"Could not parse peak precipitation value: '{val_raw}'")

    # ----------------------------------------------------------------
    # Criterion 6: VLM Trajectory Verification (25 pts)
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            vlm_images = frames + [final] if final else frames
            
            if vlm_images:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=vlm_images)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    created_1d = parsed.get("created_1d_line_plot", False)
                    reasoning = parsed.get("reasoning", "")
                    
                    if created_1d:
                        vlm_score = 25
                        feedback.append(f"VLM verified 1D Line Plot creation. Reason: {reasoning}")
                    else:
                        feedback.append(f"VLM did not detect 1D Line Plot creation. Reason: {reasoning}")
                else:
                    feedback.append("VLM query returned unsuccessful response.")
            else:
                feedback.append("No trajectory images available for VLM verification.")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback.append(f"VLM verification error: {e}")
            
        score += vlm_score
    else:
        # If VLM is not available, scale the 75-point score to 100
        feedback.append("VLM verification not available, scaling programmatic score to 100")
        score = int(score * (100.0 / 75.0))

    # Final decision
    # Ensure they at least exported the file and got the month/values somewhat right
    key_criteria_met = plot_exists and (month_raw.lower() in ['january', 'jan', '01', '1'])
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }