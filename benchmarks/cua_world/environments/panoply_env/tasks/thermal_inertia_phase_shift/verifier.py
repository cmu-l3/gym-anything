#!/usr/bin/env python3
"""
Verifier for thermal_inertia_phase_shift task.

Evaluates multi-signal criteria:
1. File Generation (15 pts): 3 PNGs exist, sizes > 10KB, created after task start.
2. Report Structure (10 pts): All keys parsed from the text report.
3. Peak Months Correct (15 pts): Land = July, Ocean = August.
4. Physical Mechanism (10 pts): Mentions "heat capacity" or "thermal inertia".
5. Land Temp Accuracy (15 pts): 292-304 K (or 19-31 °C).
6. Ocean Temp Accuracy (15 pts): 285-293 K (or 11-20 °C).
7. VLM Trajectory Check (20 pts): Confirms the agent actively manipulated 1D line 
   plots and spatial maps in the application during the trajectory.
"""

import json
import os
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot


def verify_thermal_inertia_phase_shift(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON securely
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/thermal_inertia_phase_shift_result.json', tmp.name)
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
    # 1. File Generation (15 pts)
    # ----------------------------------------------------------------
    land_plot_ok = result.get('land_plot_exists', False) and result.get('land_plot_mtime', 0) >= task_start and result.get('land_plot_size', 0) > 10000
    ocean_plot_ok = result.get('ocean_plot_exists', False) and result.get('ocean_plot_mtime', 0) >= task_start and result.get('ocean_plot_size', 0) > 10000
    map_plot_ok = result.get('map_plot_exists', False) and result.get('map_plot_mtime', 0) >= task_start and result.get('map_plot_size', 0) > 10000
    report_ok = result.get('report_exists', False) and result.get('report_mtime', 0) >= task_start

    if land_plot_ok and ocean_plot_ok and map_plot_ok and report_ok:
        score += 15
        feedback.append("All output files generated successfully during task.")
    else:
        feedback.append("Missing or undersized output files (or created before task start).")

    # ----------------------------------------------------------------
    # 2. Report Structure (10 pts)
    # ----------------------------------------------------------------
    land_month = result.get('land_peak_month', '').strip().lower()
    ocean_month = result.get('ocean_peak_month', '').strip().lower()
    land_temp_str = result.get('land_peak_temp', '').strip()
    ocean_temp_str = result.get('ocean_peak_temp', '').strip()
    mechanism = result.get('mechanism', '').strip().lower()
    phase_shift = result.get('phase_shift', '').strip()

    has_all_keys = bool(land_month and ocean_month and land_temp_str and ocean_temp_str and mechanism and phase_shift)
    
    if has_all_keys:
        score += 10
        feedback.append("Report contains all required structured fields.")
    else:
        feedback.append("Report is missing one or more required fields.")

    # ----------------------------------------------------------------
    # 3. Peak Months Correct (15 pts)
    # ----------------------------------------------------------------
    months_correct = 0
    if 'jul' in land_month:
        months_correct += 1
    if 'aug' in ocean_month:
        months_correct += 1

    if months_correct == 2:
        score += 15
        feedback.append("Correctly identified Land peak (July) and Ocean peak (August).")
    elif months_correct == 1:
        score += 7
        feedback.append("Partially correct on peak months.")
    else:
        feedback.append(f"Incorrect peak months. Land reported: {land_month}, Ocean reported: {ocean_month}.")

    # ----------------------------------------------------------------
    # 4. Physical Mechanism (10 pts)
    # ----------------------------------------------------------------
    if 'heat capacity' in mechanism or 'thermal inertia' in mechanism:
        score += 10
        feedback.append("Physical mechanism correctly identified.")
    else:
        feedback.append(f"Physical mechanism incorrect or not specific enough: '{mechanism}'.")

    # ----------------------------------------------------------------
    # Helper to parse temperature numerical values safely
    # ----------------------------------------------------------------
    def parse_temp(val_str):
        m = re.search(r'-?\d+\.?\d*', val_str)
        return float(m.group()) if m else None

    # ----------------------------------------------------------------
    # 5. Land Temp Accuracy (15 pts)
    # Target: ~298 K (or ~25 °C). Range: 292-304 K (or 19-31 °C).
    # ----------------------------------------------------------------
    land_temp = parse_temp(land_temp_str)
    if land_temp is not None:
        if 292.0 <= land_temp <= 304.0:
            score += 15
            feedback.append(f"Land peak temperature {land_temp}K is mathematically accurate.")
        elif 19.0 <= land_temp <= 31.0:
            score += 15
            feedback.append(f"Land peak temperature {land_temp}°C is mathematically accurate.")
        else:
            feedback.append(f"Land peak temperature {land_temp} is outside the valid range.")
    else:
        feedback.append("Could not parse numerical value for Land peak temperature.")

    # ----------------------------------------------------------------
    # 6. Ocean Temp Accuracy (15 pts)
    # Target: ~289 K (or ~16 °C). Range: 284-293 K (or 11-20 °C).
    # ----------------------------------------------------------------
    ocean_temp = parse_temp(ocean_temp_str)
    if ocean_temp is not None:
        if 284.0 <= ocean_temp <= 293.0:
            score += 15
            feedback.append(f"Ocean peak temperature {ocean_temp}K is mathematically accurate.")
        elif 11.0 <= ocean_temp <= 20.0:
            score += 15
            feedback.append(f"Ocean peak temperature {ocean_temp}°C is mathematically accurate.")
        else:
            feedback.append(f"Ocean peak temperature {ocean_temp} is outside the valid range.")
    else:
        feedback.append("Could not parse numerical value for Ocean peak temperature.")

    # ----------------------------------------------------------------
    # 7. VLM Trajectory Check (20 pts)
    # Prevents purely hallucinating the text file without touching the UI.
    # ----------------------------------------------------------------
    vlm_passed = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        prompt = """
        Review these screenshots from an agent operating NASA Panoply. 
        Did the agent successfully create and view AT LEAST ONE 1D line plot 
        (a chart with a single line plotted across an X-axis) and AT LEAST ONE 2D spatial map during the session?
        
        Respond in JSON format:
        {
            "shows_1d_line_plot": true/false,
            "shows_2d_spatial_map": true/false,
            "reasoning": "Brief explanation"
        }
        """
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("shows_1d_line_plot") and parsed.get("shows_2d_spatial_map"):
                    score += 20
                    vlm_passed = True
                    feedback.append("VLM confirmed visual presence of line plot and spatial map workflows.")
                else:
                    feedback.append(f"VLM check failed. Reasoning: {parsed.get('reasoning')}")
        except Exception as e:
            feedback.append(f"VLM verification exception: {e}")
    else:
        feedback.append("VLM unavailable - skipping trajectory visual verification.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }