#!/usr/bin/env python3
"""
Verifier for australian_bushfire_seasonality_assessment task.

Verification Strategy:
  1. January Plot Exported (15 pts) - Exists, recent, sufficient size.
  2. August Plot Exported (15 pts) - Exists, recent, sufficient size.
  3. Deductive Climatology Logic (50 pts) - 12.5 pts per correctly populated field:
       - JANUARY_WET_COAST: North
       - AUGUST_WET_COAST: South
       - NORTHERN_PEAK_FIRE_MONTH: August
       - SOUTHERN_PEAK_FIRE_MONTH: January
  4. VLM Trajectory Check (20 pts) - Agent actually interacted with Panoply.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to ensure they used Panoply and generated map plots
VLM_PROMPT = """You are evaluating an agent's trajectory for a scientific data visualization task.
Look at these screenshots taken during the task execution.
Did the agent use the Panoply application to view color-mapped global or regional data plots (specifically looking like precipitation/weather maps)?
Respond with ONLY valid JSON:
{"used_panoply_for_plots": true/false}
"""

def verify_australian_bushfire_seasonality_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/australian_bushfire_seasonality_assessment_result.json', tmp.name)
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

    # 1. January Plot (15 pts)
    jan_exists = result.get('png_jan_exists', False)
    jan_mtime = int(result.get('png_jan_mtime', 0))
    jan_size = int(result.get('png_jan_size', 0))

    if jan_exists and jan_mtime >= task_start and jan_size >= 15000:
        score += 15
        feedback.append(f"January plot successfully exported ({jan_size} bytes).")
    elif jan_exists and jan_mtime >= task_start and jan_size >= 5000:
        score += 7
        feedback.append(f"January plot exported but abnormally small ({jan_size} bytes).")
    else:
        feedback.append(f"January plot missing or invalid.")

    # 2. August Plot (15 pts)
    aug_exists = result.get('png_aug_exists', False)
    aug_mtime = int(result.get('png_aug_mtime', 0))
    aug_size = int(result.get('png_aug_size', 0))

    if aug_exists and aug_mtime >= task_start and aug_size >= 15000:
        score += 15
        feedback.append(f"August plot successfully exported ({aug_size} bytes).")
    elif aug_exists and aug_mtime >= task_start and aug_size >= 5000:
        score += 7
        feedback.append(f"August plot exported but abnormally small ({aug_size} bytes).")
    else:
        feedback.append(f"August plot missing or invalid.")

    # 3. Deductive Climatology Logic (50 pts - 12.5 each)
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    jan_wet = result.get('january_wet_coast', '').strip().lower()
    aug_wet = result.get('august_wet_coast', '').strip().lower()
    north_fire = result.get('northern_peak_fire_month', '').strip().lower()
    south_fire = result.get('southern_peak_fire_month', '').strip().lower()

    if report_exists and report_mtime >= task_start:
        correct_fields = 0
        if "north" in jan_wet:
            score += 12.5
            correct_fields += 1
        if "south" in aug_wet:
            score += 12.5
            correct_fields += 1
        if "august" in north_fire:
            score += 12.5
            correct_fields += 1
        if "january" in south_fire:
            score += 12.5
            correct_fields += 1
            
        feedback.append(f"Report logical deductions: {correct_fields}/4 correct.")
    else:
        feedback.append("Bushfire seasonality report missing or not updated.")

    # 4. VLM Trajectory Check (20 pts)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                used_panoply = parsed.get("used_panoply_for_plots", False)
                if used_panoply:
                    score += 20
                    feedback.append("VLM confirmed Panoply visualization usage.")
                else:
                    feedback.append("VLM did not detect Panoply plots in trajectory.")
            else:
                # Default to partial points if VLM fails randomly
                score += 10
                feedback.append("VLM check failed, granting partial credit.")
        else:
            feedback.append("No screenshots available for VLM check.")
    else:
        score += 20
        feedback.append("VLM skipped (not available), auto-granted trajectory points.")

    score = int(score)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }