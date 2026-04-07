#!/usr/bin/env python3
"""
Verifier for Stakeout Calculation (Replanteo) task in TopoCal.

Verifies:
1. The stakeholder report was created during the task.
2. The report contains reference to all target points.
3. The azimuths and distances match the computed ground truth within tolerance.
4. Trajectory frames show actual interaction with the software (VLM check).
"""

import json
import tempfile
import os
import re
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully used the 'Replanteo' (Stakeout) tool in TopoCal.

Examine these trajectory screenshots and determine:
1. Did the agent open the Replanteo/Stakeout menu or calculation dialog?
2. Did the agent configure Point 1 as the instrument base station?
3. Are the target points (5, 12, 18, 25, 31) selected or visible in a results table?

Respond exactly in JSON format:
{
    "opened_stakeout_tool": true/false,
    "configured_station": true/false,
    "targets_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def extract_values_for_point(point_id, file_content):
    """
    Attempts to extract azimuth and distance for a specific point from unstructured text.
    Looks for a line containing the point ID, then extracts float values.
    Returns (azimuth, distance) or (None, None).
    """
    lines = file_content.split('\n')
    for line in lines:
        # Match lines that explicitly denote the point (e.g. "Pt 5", "Point 5", or just "5" at start)
        match = re.search(rf'(?:(?:Pt|Point|Punto|P)\s*)?\b{point_id}\b', line, re.IGNORECASE)
        if match:
            # Find all decimal numbers in the line
            numbers = re.findall(r'\b\d{1,4}\.\d{1,4}\b', line)
            if len(numbers) >= 2:
                # Typically Azimuth is [0-360] and Distance is positive
                num1 = float(numbers[0])
                num2 = float(numbers[1])
                
                # Try to logically assign Azimuth and Distance
                # If one is > 360, it MUST be the distance
                if num1 > 360:
                    return (num2, num1)
                elif num2 > 360:
                    return (num1, num2)
                else:
                    # Default assumption: Azimuth comes first, then Distance
                    return (num1, num2)
    return (None, None)

def verify_stakeout_calculation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    az_tol = metadata.get('azimuth_tolerance_deg', 0.5)
    dist_tol = metadata.get('distance_tolerance_m', 0.5)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Read task execution metadata
    # -------------------------------------------------------------------------
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)

    if output_exists:
        score += 10
        feedback_parts.append("Report file exists")
        if file_created_during_task:
            score += 5
            feedback_parts.append("Report created during task")
        else:
            feedback_parts.append("Warning: Report file existed before task (possible gaming)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Stakeout report file was not found at the expected location."
        }

    # -------------------------------------------------------------------------
    # 2. Read Ground Truth
    # -------------------------------------------------------------------------
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = None
    try:
        copy_from_env("C:\\ProgramData\\task_verification\\stakeout_ground_truth.json", tmp_gt.name)
        with open(tmp_gt.name, 'r', encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read ground truth: {e}")
    finally:
        if os.path.exists(tmp_gt.name):
            os.unlink(tmp_gt.name)

    if not gt_data or "targets" not in gt_data:
        return {"passed": False, "score": score, "feedback": "Verifier error: Ground truth missing."}

    # -------------------------------------------------------------------------
    # 3. Parse and Validate Report
    # -------------------------------------------------------------------------
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    report_content = ""
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\TopoCal\\stakeout_report.txt", tmp_report.name)
        with open(tmp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        logger.error(f"Failed to read report text: {e}")
    finally:
        if os.path.exists(tmp_report.name):
            os.unlink(tmp_report.name)

    gt_targets = {t["id"]: t for t in gt_data["targets"]}
    
    pts_found = 0
    azimuths_correct = 0
    distances_correct = 0

    for pt_id, gt_vals in gt_targets.items():
        az_extracted, dist_extracted = extract_values_for_point(pt_id, report_content)
        
        if az_extracted is not None and dist_extracted is not None:
            pts_found += 1
            
            # Check Azimuth
            gt_az = gt_vals["azimuth_deg"]
            # Handle 360 wrap-around tolerance
            az_diff = abs(az_extracted - gt_az)
            if az_diff <= az_tol or abs(az_diff - 360) <= az_tol:
                azimuths_correct += 1
                score += 5  # 5 points per correct azimuth (max 25)
            
            # Check Distance
            gt_dist = gt_vals["horiz_dist_m"]
            if abs(dist_extracted - gt_dist) <= dist_tol:
                distances_correct += 1
                score += 4  # 4 points per correct distance (max 20)

    score += (pts_found * 2)  # 2 points per referenced target (max 10)
    
    feedback_parts.append(f"Found {pts_found}/5 targets in text")
    feedback_parts.append(f"Correct Azimuths: {azimuths_correct}/5")
    feedback_parts.append(f"Correct Distances: {distances_correct}/5")

    # -------------------------------------------------------------------------
    # 4. VLM Trajectory Verification
    # -------------------------------------------------------------------------
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("opened_stakeout_tool"):
                    score += 5
                if parsed.get("configured_station") or parsed.get("targets_visible"):
                    score += 5
                feedback_parts.append("VLM verified tool usage")

    # Determine pass/fail
    key_criteria_met = (azimuths_correct >= 3 and distances_correct >= 3 and file_created_during_task)
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }