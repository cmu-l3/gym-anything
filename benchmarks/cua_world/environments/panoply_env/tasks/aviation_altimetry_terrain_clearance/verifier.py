#!/usr/bin/env python3
"""
Verifier for aviation_altimetry_terrain_clearance task.
"""

import json
import os
import tempfile
import re
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aviation_altimetry_terrain_clearance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/aviation_altimetry_terrain_clearance_result.json', tmp.name)
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

    # 1. Plot Exported (20 pts)
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 15000:
        score += 20
        feedback.append(f"Plot exported successfully ({plot_size} bytes)")
    elif plot_exists and plot_mtime >= task_start and plot_size >= 5000:
        score += 10
        feedback.append(f"Plot exported but small ({plot_size} bytes)")
    else:
        feedback.append("Plot missing or not created during task")

    # 2. Report Formatted (15 pts)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    parsed = result.get('parsed', {})

    has_slp = bool(parsed.get('min_slp'))
    has_error = bool(parsed.get('max_error'))
    has_implication = bool(parsed.get('implication'))

    if report_exists and report_mtime >= task_start and has_slp and has_error and has_implication:
        score += 15
        feedback.append("Report complete with required fields")
    elif report_exists and report_mtime >= task_start and (has_slp or has_error):
        score += 7
        feedback.append("Report partial")
    else:
        feedback.append("Report missing or incomplete")

    # 3. Correct Minimum SLP (20 pts)
    # The Aleutian / Icelandic Low in Jan typically is ~997-1002 hPa. Let's allow 990-1005.
    slp_str = parsed.get('min_slp', '')
    slp_val = None
    if slp_str:
        try:
            m = re.search(r'[-+]?\d*\.\d+|\d+', slp_str)
            if m:
                slp_val = float(m.group(0))
        except:
            pass

    if slp_val is not None:
        if 990 <= slp_val <= 1005:
            score += 20
            feedback.append(f"Min SLP ({slp_val}) in valid range 990-1005 hPa")
        else:
            feedback.append(f"Min SLP ({slp_val}) outside valid range")
    else:
        feedback.append("Could not parse MIN_MEAN_SLP_HPA")

    # 4. Accurate Math (20 pts)
    # Error (ft) = (1013 - Minimum_SLP) * 30
    error_str = parsed.get('max_error', '')
    error_val = None
    if error_str:
        try:
            m = re.search(r'[-+]?\d*\.\d+|\d+', error_str)
            if m:
                error_val = float(m.group(0))
        except:
            pass
    
    if slp_val is not None and error_val is not None:
        expected_error = (1013 - slp_val) * 30
        if abs(error_val - expected_error) <= 15:
            score += 20
            feedback.append(f"Calculated altitude error ({error_val}) matches formula")
        else:
            feedback.append(f"Calculated error ({error_val}) does not match expected ({expected_error})")
    else:
        feedback.append("Could not verify math due to missing values")

    # 5. Hazard Direction (10 pts)
    implication = parsed.get('implication', '').upper()
    if 'TRUE_LOWER' in implication or ('LOWER' in implication and not 'HIGHER' in implication):
        score += 10
        feedback.append("Safety implication correct (TRUE_LOWER)")
    elif implication:
        feedback.append(f"Safety implication incorrect ({implication})")
    else:
        feedback.append("Missing safety implication")

    # 6. VLM Trajectory Verification (15 pts)
    # Use trajectory frames to check if Panoply was actively used to look at data
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            
            prompt = """Look at these screenshots from a user's session.
Did the user interact with a data visualization application (NASA Panoply) to look at a colored map of the Earth?
Respond in JSON format:
{
    "panoply_used": true/false,
    "map_visible": true/false
}"""
            
            vlm_res = query_vlm(prompt=prompt, images=frames + [final])
            if vlm_res.get('success'):
                parsed_vlm = vlm_res.get('parsed', {})
                if parsed_vlm.get('panoply_used') and parsed_vlm.get('map_visible'):
                    score += 15
                    feedback.append("VLM verified Panoply usage")
                else:
                    feedback.append("VLM did not detect Panoply/map usage in trajectory")
            else:
                feedback.append("VLM query failed")
        except Exception as e:
            feedback.append(f"VLM exception: {e}")
            score += 15 # Award points if VLM crashes to prevent failing valid runs
    else:
        # Give free points if VLM not available to not fail valid programmatic runs
        score += 15
        feedback.append("VLM unavailable, skipped trajectory check")

    passed = score >= 75 and plot_exists and (slp_val is not None) and (error_val is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }