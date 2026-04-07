#!/usr/bin/env python3
"""
Verifier for siberian_ice_road_logistics task.

Evaluates 1D and 2D plot creation in NASA Panoply and domain-specific data extraction.
"""

import json
import os
import re
import tempfile

def verify_siberian_ice_road_logistics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/siberian_ice_road_logistics_result.json', tmp.name)
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
    # Criterion 1: 2D Spatial Map Exported (15 pts)
    # ----------------------------------------------------------------
    map_exists = result.get('map_plot_exists', False)
    map_mtime = int(result.get('map_plot_mtime', 0))
    map_size = int(result.get('map_plot_size', 0))

    if map_exists and map_mtime >= task_start and map_size >= 15000:
        score += 15
        feedback.append(f"January map plot exported ({map_size} bytes)")
    elif map_exists and map_mtime >= task_start and map_size >= 5000:
        score += 7
        feedback.append(f"January map plot present but small ({map_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"January map plot missing or not created during task (exists={map_exists})")

    # ----------------------------------------------------------------
    # Criterion 2: 1D Line Plot Exported (15 pts)
    # ----------------------------------------------------------------
    line_exists = result.get('line_plot_exists', False)
    line_mtime = int(result.get('line_plot_mtime', 0))
    line_size = int(result.get('line_plot_size', 0))

    # Line plots are typically smaller than spatial maps
    if line_exists and line_mtime >= task_start and line_size >= 8000:
        score += 15
        feedback.append(f"Annual profile line plot exported ({line_size} bytes)")
    elif line_exists and line_mtime >= task_start and line_size >= 3000:
        score += 7
        feedback.append(f"Line plot present but small ({line_size} bytes, expected >=8KB)")
    else:
        feedback.append(f"Annual profile line plot missing or not created during task (exists={line_exists})")

    # ----------------------------------------------------------------
    # Criterion 3: Logistics Report Fields (15 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    location = result.get('location', '').strip()
    threshold_k = result.get('threshold_k', '').strip()
    safe_months = result.get('safe_months', '').strip().lower()
    jan_min_temp_k = result.get('jan_min_temp_k', '').strip()

    has_loc = bool(location)
    has_thresh = bool(threshold_k)
    has_months = bool(safe_months)
    has_temp = bool(jan_min_temp_k)

    if report_exists and report_mtime >= task_start and has_loc and has_thresh and has_months and has_temp:
        score += 15
        feedback.append("Report successfully created with all required fields")
    elif report_exists and report_mtime >= task_start:
        score += 5
        feedback.append("Report created but missing some required fields")
    else:
        feedback.append("Report missing or not created during task")

    # ----------------------------------------------------------------
    # Criterion 4: Logical Threshold & Temperature Accuracy (30 pts)
    # ----------------------------------------------------------------
    try:
        # Clean numeric fields
        thresh_val = float(re.sub(r'[^\d\.]', '', threshold_k)) if threshold_k else 0.0
        temp_val = float(re.sub(r'[^\d\.]', '', jan_min_temp_k)) if jan_min_temp_k else 0.0

        if abs(thresh_val - 253.15) <= 1.0:
            score += 10
            feedback.append(f"Threshold accurate ({thresh_val} K)")
        else:
            feedback.append(f"Threshold incorrect (expected ~253.15 K, got {thresh_val})")

        # NCEP LTM Jan temp for Yakutsk (~62.5N, 130E) is ~233K (-40C). Allow 225-245K.
        if 225.0 <= temp_val <= 245.0:
            score += 10
            feedback.append(f"January min temp physically plausible ({temp_val} K)")
        else:
            feedback.append(f"January min temp incorrect (expected 225-245 K, got {temp_val})")

        # Check safe months (Dec, Jan, Feb definitely below -20C, Jul/Aug definitely above)
        winter_found = any(m in safe_months for m in ['jan', 'feb', 'dec'])
        summer_found = any(m in safe_months for m in ['jul', 'aug'])

        if winter_found and not summer_found:
            score += 10
            feedback.append("Safe months logic correctly identifies winter and excludes summer")
        else:
            feedback.append(f"Safe months logic flawed (Winter found: {winter_found}, Summer found: {summer_found})")
            
    except Exception as e:
        feedback.append(f"Error parsing numeric values from report: {e}")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Trajectory Verification (25 pts)
    # Proves the agent actually used the Panoply UI to create a Line Plot
    # ----------------------------------------------------------------
    vlm_score = 0
    if query_vlm:
        try:
            # We sample trajectory frames to see if the Line Plot window was opened
            # In gym_anything, sample_trajectory_frames gets intermediate frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)

            if frames:
                vlm_prompt = """Review these screenshots of an agent using NASA Panoply. 
Look closely at the various windows. Did the agent successfully create and display a '1D Line Plot' 
(a time-series graph showing a curve or line over an axis, rather than just a 2D geographic map)?
Reply in JSON format:
{
  "created_line_plot": true/false,
  "reasoning": "brief description of why"
}"""
                vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("created_line_plot", False):
                        vlm_score = 25
                        feedback.append("VLM confirmed 1D Line Plot was created during workflow.")
                    else:
                        feedback.append("VLM did not detect the creation of a 1D Line Plot.")
                else:
                    feedback.append("VLM verification failed to parse.")
        except Exception as e:
            feedback.append(f"VLM exception: {e}")
    else:
        feedback.append("VLM not available, skipping trajectory visual check.")
        # If VLM is not available, we give partial credit if the file exists
        if line_exists:
            vlm_score = 15

    score += vlm_score

    # Final logic
    key_criteria_met = map_exists and line_exists and report_exists and (winter_found and not summer_found)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }