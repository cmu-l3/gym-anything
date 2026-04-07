#!/usr/bin/env python3
"""
Verifier for greenland_ablation_onset_analysis task.

Criteria:
1. April Plot exported (15 points)
2. July Plot exported (15 points)
3. Report structure and completeness (20 points)
4. Scientific Logic (Threshold correctly identified ~273.15, Margins melting in July, Interior frozen) (20 points)
5. VLM trajectory verification: Used a North Polar projection focused on Greenland (30 points)
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an expert GIS and climate visualization evaluator. Review these screenshots of an agent using NASA Panoply to analyze the Greenland Ice Sheet.

Determine if the agent successfully changed the map projection to an appropriate North Polar projection (e.g., North Polar Stereographic, North Polar Orthographic) and focused the view on Greenland.

CRITICAL: 
- By default, Panoply uses a global Equirectangular projection that severely stretches Greenland horizontally at the top of the map. This is INCORRECT for this task.
- A CORRECT projection will show the Arctic/Greenland from a "top-down" circular or localized perspective without extreme horizontal smearing.

Reply in JSON format:
{
    "used_polar_projection": true/false,
    "focused_on_greenland": true/false,
    "reasoning": "brief explanation of the visual evidence"
}
"""

def verify_greenland_ablation_onset_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/greenland_ablation_onset_analysis_result.json', tmp.name)
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

    # 1. April Plot (15 pts)
    april_exists = result.get('png_april_exists', False)
    april_mtime = int(result.get('png_april_mtime', 0))
    april_size = int(result.get('png_april_size', 0))

    if april_exists and april_mtime >= task_start and april_size >= 15000:
        score += 15
        feedback.append("April diagnostic plot correctly exported.")
    elif april_exists and april_mtime >= task_start:
        score += 7
        feedback.append(f"April plot exported but file size is suspiciously small ({april_size} bytes).")
    else:
        feedback.append("April diagnostic plot missing or not created during task.")

    # 2. July Plot (15 pts)
    july_exists = result.get('png_july_exists', False)
    july_mtime = int(result.get('png_july_mtime', 0))
    july_size = int(result.get('png_july_size', 0))

    if july_exists and july_mtime >= task_start and july_size >= 15000:
        score += 15
        feedback.append("July diagnostic plot correctly exported.")
    elif july_exists and july_mtime >= task_start:
        score += 7
        feedback.append(f"July plot exported but file size is suspiciously small ({july_size} bytes).")
    else:
        feedback.append("July diagnostic plot missing or not created during task.")

    # 3. Report completeness (20 pts)
    melt_threshold = result.get('melt_threshold', '').strip()
    april_status = result.get('april_status', '').strip().lower()
    july_margin = result.get('july_margin_status', '').strip().lower()
    july_interior = result.get('july_interior_status', '').strip().lower()

    if melt_threshold and april_status and july_margin and july_interior:
        score += 20
        feedback.append("Report contains all required structural fields.")
    else:
        feedback.append("Report is missing one or more required fields.")

    # 4. Scientific Logic (20 pts)
    logic_score = 0
    # Check threshold (accept 273.15, 273, or 0 if they noted Celsius somehow)
    try:
        threshold_val = float(re.sub(r'[^\d\.]', '', melt_threshold))
        if 273.0 <= threshold_val <= 274.0:
            logic_score += 5
            feedback.append("Correctly identified melt threshold (~273.15 K).")
        elif threshold_val == 0.0:
            logic_score += 5
            feedback.append("Identified 0 C as threshold.")
    except ValueError:
        pass

    # Check April (Frozen)
    if 'froz' in april_status or 'solid' in april_status or 'no' in april_status or 'below' in april_status:
        logic_score += 5
    
    # Check July Margins (Melting)
    if 'melt' in july_margin or 'thaw' in july_margin or 'above' in july_margin or 'yes' in july_margin:
        logic_score += 5

    # Check July Interior (Frozen)
    if 'froz' in july_interior or 'solid' in july_interior or 'no' in july_interior or 'below' in july_interior:
        logic_score += 5

    score += logic_score
    if logic_score == 20:
        feedback.append("Scientific deductions are fully correct.")
    else:
        feedback.append(f"Scientific deductions are partially correct or missing ({logic_score}/20 pts).")

    # 5. VLM Verification (30 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
        
        if frames:
            vlm_resp = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                used_polar = parsed.get("used_polar_projection", False)
                focused_gr = parsed.get("focused_on_greenland", False)
                
                if used_polar and focused_gr:
                    vlm_score = 30
                    feedback.append("VLM confirms agent successfully applied a North Polar projection and focused on Greenland.")
                elif used_polar or focused_gr:
                    vlm_score = 15
                    feedback.append(f"VLM indicates partial projection success: Polar={used_polar}, Greenland={focused_gr}.")
                else:
                    feedback.append("VLM indicates agent failed to apply an appropriate North Polar projection. Equirectangular distortion present.")
            else:
                feedback.append("VLM query failed during verification.")
        else:
            feedback.append("No trajectory frames available for VLM verification.")
    else:
        feedback.append("VLM endpoint not available; cannot verify projection usage.")
    
    score += vlm_score

    # Final logic
    key_criteria = april_exists and july_exists and (logic_score >= 10)
    passed = (score >= 80) and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }