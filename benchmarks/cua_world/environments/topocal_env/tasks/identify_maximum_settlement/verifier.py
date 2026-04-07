#!/usr/bin/env python3
"""
Verifier for identify_maximum_settlement task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Output Report Validation (File presence, formatting, anti-gaming timestamps).
2. Location Accuracy: Euclidean distance to true epicenter.
3. Magnitude Accuracy: Proximity to true vertical displacement.
4. VLM Verification: Analyzes trajectory to ensure CAD software was actually used.
"""

import json
import os
import re
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully completed a topographic CAD task.
The agent was asked to import survey data and compare two terrain surfaces using TopoCal (or similar CAD tool).

Look at the provided trajectory frames and the final screenshot and determine:
1. Is a topographic CAD software interface clearly visible during the trajectory?
2. Are there indications of point clouds, terrain triangulations (TIN/MDT), contour lines, or difference grids visible in the drawing area?

Respond in JSON format:
{
    "cad_software_used": true/false,
    "terrain_models_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what visual evidence you see"
}
"""

def verify_identify_maximum_settlement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', 'C:\\workspace\\data\\max_settlement_report.txt')
    true_x = metadata.get('ground_truth_x', 481100.0)
    true_y = metadata.get('ground_truth_y', 4398050.0)
    true_mag = metadata.get('ground_truth_settlement', -0.285)
    tols = metadata.get('tolerances', {})

    score = 0
    feedback_parts = []
    
    # 1. READ EXPORTED SYSTEM JSON
    sys_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", sys_temp.name)
        with open(sys_temp.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(sys_temp.name):
            os.unlink(sys_temp.name)

    output_exists = result_meta.get('output_exists', False)
    file_created_during_task = result_meta.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Report file was not found."}
    if not file_created_during_task:
        return {"passed": False, "score": 0, "feedback": "Anti-Gaming failure: File was not created/modified during the task run."}

    # 2. READ & PARSE THE REPORT TEXT
    report_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    reported_x, reported_y, reported_mag = None, None, None
    try:
        copy_from_env(expected_path, report_temp.name)
        with open(report_temp.name, 'r', encoding='utf-8') as f:
            content = f.read()

        # Extract values using regex to tolerate slight formatting variations
        match_x = re.search(r'X:\s*([-+]?\d*\.?\d+)', content, re.IGNORECASE)
        match_y = re.search(r'Y:\s*([-+]?\d*\.?\d+)', content, re.IGNORECASE)
        match_mag = re.search(r'Magnitude:\s*([-+]?\d*\.?\d+)', content, re.IGNORECASE)

        if match_x: reported_x = float(match_x.group(1))
        if match_y: reported_y = float(match_y.group(1))
        if match_mag: reported_mag = float(match_mag.group(1))

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read/parse report file: {e}"}
    finally:
        if os.path.exists(report_temp.name):
            os.unlink(report_temp.name)

    if None in (reported_x, reported_y, reported_mag):
        return {"passed": False, "score": 0, "feedback": "File exists but required values (X, Y, Magnitude) were not fully parsed. Check format."}

    score += 10
    feedback_parts.append("✅ File parsed successfully")

    # 3. EVALUATE LOCATION ACCURACY (30 pts max)
    distance_error = math.sqrt((reported_x - true_x)**2 + (reported_y - true_y)**2)
    location_score = 0
    if distance_error <= tols.get('location_fine_m', 1.0):
        location_score = 30
        feedback_parts.append(f"✅ Location highly accurate (err: {distance_error:.2f}m)")
    elif distance_error <= tols.get('location_coarse_m', 5.0):
        location_score = 15
        feedback_parts.append(f"⚠️ Location loosely accurate (err: {distance_error:.2f}m)")
    else:
        feedback_parts.append(f"❌ Location inaccurate (err: {distance_error:.2f}m)")
    score += location_score

    # 4. EVALUATE MAGNITUDE ACCURACY (30 pts max)
    mag_error = abs(reported_mag - true_mag)
    mag_score = 0
    if mag_error <= tols.get('magnitude_fine_m', 0.01):
        mag_score = 30
        feedback_parts.append(f"✅ Magnitude highly accurate (err: {mag_error:.3f}m)")
    elif mag_error <= tols.get('magnitude_coarse_m', 0.05):
        mag_score = 15
        feedback_parts.append(f"⚠️ Magnitude loosely accurate (err: {mag_error:.3f}m)")
    else:
        feedback_parts.append(f"❌ Magnitude inaccurate (err: {mag_error:.3f}m)")
    score += mag_score

    # 5. VLM TRAJECTORY VERIFICATION (30 pts)
    # Proves the agent actually used the software rather than writing a python script to cheat the answer
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        vlm_resp = query_vlm(prompt=VLM_PROMPT, images=frames)
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('cad_software_used') and parsed.get('terrain_models_visible'):
                score += 30
                feedback_parts.append("✅ VLM confirmed CAD workflow execution")
            else:
                feedback_parts.append("❌ VLM did not observe terrain CAD workflow")
        else:
            feedback_parts.append("⚠️ VLM verification failed to execute")

    passed = (score >= 60) and (location_score > 0) and (mag_score > 0)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }