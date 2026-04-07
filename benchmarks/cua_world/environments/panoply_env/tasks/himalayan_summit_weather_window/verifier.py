#!/usr/bin/env python3
"""
Verifier for himalayan_summit_weather_window task.

Evaluates:
  1. Precipitation plots exported (May and July) (20 points)
  2. Temperature plot exported (May) (10 points)
  3. Map zooming/bounding correctly applied (VLM Trajectory check) (30 points)
  4. Correct Hazard Identification (May vs July) (20 points)
  5. Accurate Unit Conversion for Mountain Temp (C) (20 points)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_ZOOM_PROMPT = """
You are verifying if a computer agent successfully zoomed into a specific geographic region in NASA Panoply.
The task required the agent to restrict the map bounds to the Himalayan / South Asian region (approx Lat 20°N-40°N, Lon 70°E-95°E).

Look at the Panoply map plots shown in these screens (especially the later ones showing exported maps or the map view).
Determine:
1. Are the maps displaying a global view of the earth?
2. Or did the user successfully restrict the Min/Max Latitude and Longitude to zoom in on India/Nepal/Tibet (the Himalayas)?

Respond ONLY in valid JSON format:
{
    "is_global_map": true/false,
    "is_zoomed_to_himalayas": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what geography is visible."
}
"""

def verify_himalayan_summit_weather_window(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Fetch JSON result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/himalayan_summit_weather_window_result.json', tmp.name)
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

    # 2. Check Precipitation Plots (20 pts)
    p_may_exists = result.get('precip_may_exists', False)
    p_may_mtime = int(result.get('precip_may_mtime', 0))
    p_may_size = int(result.get('precip_may_size', 0))
    
    p_jul_exists = result.get('precip_july_exists', False)
    p_jul_mtime = int(result.get('precip_july_mtime', 0))
    p_jul_size = int(result.get('precip_july_size', 0))

    if (p_may_exists and p_may_mtime >= task_start and p_may_size >= 10000) and \
       (p_jul_exists and p_jul_mtime >= task_start and p_jul_size >= 10000):
        score += 20
        feedback.append("Both May and July precipitation plots correctly exported.")
    elif (p_may_exists and p_may_size > 5000) or (p_jul_exists and p_jul_size > 5000):
        score += 10
        feedback.append("Only one precipitation plot correctly exported, or sizes were unusually small.")
    else:
        feedback.append("Precipitation plots missing or not created during task.")

    # 3. Check Temperature Plot (10 pts)
    t_may_exists = result.get('temp_may_exists', False)
    t_may_mtime = int(result.get('temp_may_mtime', 0))
    t_may_size = int(result.get('temp_may_size', 0))

    if t_may_exists and t_may_mtime >= task_start and t_may_size >= 10000:
        score += 10
        feedback.append("May temperature plot correctly exported.")
    else:
        feedback.append("Temperature plot missing or not created during task.")

    # 4. Check Report Contents - Hazard ID (20 pts)
    report_exists = result.get('report_exists', False)
    pref_month = result.get('preferred_month', '').lower()
    haz_month = result.get('avalanche_hazard_month', '').lower()

    if report_exists:
        if 'may' in pref_month and 'jul' in haz_month:
            score += 20
            feedback.append("Hazard Identification correct: Preferred May, Hazard July.")
        else:
            feedback.append(f"Hazard Identification failed. Found pref='{pref_month}', haz='{haz_month}'")
    else:
        feedback.append("Report not found for Hazard Identification check.")

    # 5. Check Report Contents - Temperature Unit conversion (20 pts)
    temp_c_str = result.get('may_mountain_temp_c', '').replace('C', '').replace('°', '').strip()
    if report_exists and temp_c_str:
        try:
            temp_c = float(temp_c_str)
            if -35.0 <= temp_c <= 10.0:  # Valid bounds for Himalayas in May in C
                score += 20
                feedback.append(f"Temperature value ({temp_c}°C) is physically plausible for the Himalayas in May.")
            elif temp_c > 250:
                feedback.append(f"Temperature value ({temp_c}) appears to be in Kelvin, not Celsius as requested.")
            else:
                feedback.append(f"Temperature value ({temp_c}°C) is outside typical bounds (-35 to 10°C).")
        except ValueError:
            feedback.append(f"Could not parse temperature value: '{temp_c_str}'")
    else:
        feedback.append("Temperature value missing from report.")

    # 6. VLM Check for Regional Bounds Zoom (30 pts)
    if query_vlm:
        # Sample frames from trajectory + final screenshot to prove zoom was applied
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images_to_check = frames + [final_frame] if final_frame else frames

            if images_to_check:
                vlm_resp = query_vlm(images=images_to_check, prompt=VLM_ZOOM_PROMPT)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    is_zoomed = parsed.get("is_zoomed_to_himalayas", False)
                    is_global = parsed.get("is_global_map", True)
                    
                    if is_zoomed and not is_global:
                        score += 30
                        feedback.append("VLM confirms map plots were regionally bounded to the Himalayas.")
                    elif is_global:
                        feedback.append("VLM indicates the agent exported global maps without applying the requested regional bounds.")
                    else:
                        feedback.append("VLM could not definitively confirm regional zoom.")
                else:
                    feedback.append("VLM query failed during zoom verification.")
            else:
                feedback.append("No trajectory images available for VLM zoom check.")
        except Exception as e:
            logger.error(f"Error during VLM verification: {e}")
            feedback.append("VLM zoom verification crashed.")
    else:
        feedback.append("query_vlm function not available. Skipping zoom check.")

    # 7. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "score": score,
            "report_parsed": {
                "pref_month": pref_month,
                "haz_month": haz_month,
                "reported_temp": temp_c_str
            }
        }
    }