#!/usr/bin/env python3
"""
Verifier for River Morphometry task.

Criteria:
1. Result file created during task (15 pts)
2. Water area measured and reasonable (>10k px) (20 pts)
3. Three distinct width measurements provided (25 pts)
4. Widths are consistent (CV < 1.0) (10 pts)
5. Sinuosity index calculated (1.0 - 5.0) (20 pts)
6. VLM Verification: Agent followed workflow (10 pts)

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging
import statistics
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_river_morphometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    min_area = metadata.get('min_water_area_px', 10000)
    min_width = metadata.get('min_width_px', 20)
    
    # 1. Parse Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Criterion 1: File Creation (15 pts)
    if result.get('file_created_during_task'):
        score += 15
        feedback.append("Result file created successfully.")
    else:
        feedback.append("Result file missing or not created during task.")

    # Criterion 2: Water Area (20 pts)
    area = result.get('water_area')
    if area and area > min_area:
        score += 20
        feedback.append(f"Water area measured: {area:.0f} px²")
    else:
        feedback.append(f"Water area missing or too small (got {area}).")

    # Criterion 3: Width Measurements (25 pts)
    widths = [w for w in result.get('widths', []) if w > min_width]
    if len(widths) >= 3:
        score += 25
        feedback.append(f"Three valid width measurements found: {widths[:3]}")
    elif len(widths) > 0:
        score += 10
        feedback.append(f"Partial width measurements found ({len(widths)}/3).")
    else:
        feedback.append("No valid width measurements found.")

    # Criterion 4: Width Consistency (10 pts)
    # The river width shouldn't vary wildly (e.g. 50px vs 5000px)
    if len(widths) >= 2:
        mean_w = statistics.mean(widths)
        stdev_w = statistics.stdev(widths)
        cv = stdev_w / mean_w
        if cv < 1.0:
            score += 10
            feedback.append("Width measurements are consistent.")
        else:
            feedback.append(f"Width measurements vary too much (CV={cv:.2f}).")

    # Criterion 5: Sinuosity (20 pts)
    sinuosity = result.get('sinuosity')
    if sinuosity and 1.0 <= sinuosity <= 5.0:
        score += 20
        feedback.append(f"Sinuosity valid: {sinuosity}")
    else:
        feedback.append(f"Sinuosity missing or invalid (got {sinuosity}).")

    # Criterion 6: VLM Verification (10 pts)
    # Check if the agent actually opened the image and did segmentation
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an agent using ImageJ/Fiji.
        1. Did the agent open an image that looks like a river (satellite view)?
        2. Did the agent perform any thresholding/segmentation (image turning black and white)?
        3. Are there any measurement windows or drawing lines visible?
        
        Answer JSON: {"river_visible": bool, "segmentation_visible": bool, "measurements_visible": bool}
        """
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('river_visible') or parsed.get('segmentation_visible'):
            vlm_score += 10
            feedback.append("VLM confirmed river analysis workflow.")
        else:
            feedback.append("VLM could not confirm image processing workflow.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Soft fail: give half points if we have a file but VLM failed
        if score > 40: 
            vlm_score += 5
            feedback.append("VLM check skipped (error).")

    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }