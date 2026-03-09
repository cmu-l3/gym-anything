#!/usr/bin/env python3
"""
Verifier for document_intraop_vitals task.
Verifies that the agent correctly extracted vital signs values at specific timestamps.
"""

import json
import os
import re
import logging
import tempfile
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_intraop_vitals(traj, env_info, task_info):
    """
    Verify the intraoperative vitals documentation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    # Note: Windows paths in container need to be handled correctly
    # We copy them to temp files on the host
    container_result_path = r"C:\Users\Docker\AppData\Local\Temp\task_result.json"
    container_output_path = r"C:\Users\Docker\Documents\vitals_summary.txt"
    container_gt_path = r"C:\ProgramData\VitalTruth\vitals_gt.json"

    score = 0
    feedback_parts = []
    
    # 1. Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(container_result_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic file existence and anti-gaming
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file vitals_summary.txt was not created."}
    
    score += 10
    feedback_parts.append("File created (+10)")

    if not result_data.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "File timestamp predates task start (Anti-gaming check failed)."}
    
    score += 10
    feedback_parts.append("File modified during task (+10)")

    # 2. Load and Verify Content
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Load user output
        copy_from_env(container_output_path, temp_output.name)
        with open(temp_output.name, 'r') as f:
            user_content = f.read()
            
        # Load ground truth
        copy_from_env(container_gt_path, temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve data for content verification: {str(e)}"}
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Check Header
    if "INTRAOPERATIVE VITAL SIGNS SUMMARY" in user_content and "Case: 0006" in user_content:
        score += 5
        feedback_parts.append("Header format correct (+5)")
    else:
        feedback_parts.append("Header format incorrect")

    # Parse User Data
    # Expected lines like: 00:10:00,80,98,110
    lines = user_content.strip().split('\n')
    data_lines = []
    for line in lines:
        if re.match(r'^\d{2}:\d{2}:\d{2},', line.strip()):
            data_lines.append(line.strip())

    if len(data_lines) == 5:
        score += 5
        feedback_parts.append("Correct number of data rows (+5)")
    else:
        feedback_parts.append(f"Found {len(data_lines)} data rows, expected 5")

    # Verify Values
    tolerances = task_info.get('metadata', {}).get('tolerances', {'HR': 3, 'SpO2': 2, 'SBP': 5})
    
    correct_values = 0
    total_values = 0
    
    for line in data_lines:
        parts = line.split(',')
        if len(parts) != 4:
            continue
            
        ts, hr_str, spo2_str, sbp_str = [p.strip() for p in parts]
        
        # Normalize timestamp (handle 0:10:00 vs 00:10:00)
        if len(ts.split(':')[0]) == 1: 
            ts = "0" + ts
            
        if ts not in ground_truth:
            feedback_parts.append(f"Unknown timestamp {ts}")
            continue
            
        gt_row = ground_truth[ts]
        
        # Check HR
        total_values += 1
        if check_value(hr_str, gt_row.get('HR'), tolerances['HR']):
            correct_values += 1
            
        # Check SpO2
        total_values += 1
        if check_value(spo2_str, gt_row.get('SpO2'), tolerances['SpO2']):
            correct_values += 1
            
        # Check SBP
        total_values += 1
        if check_value(sbp_str, gt_row.get('SBP'), tolerances['SBP']):
            correct_values += 1

    # Scoring for values (Max 45 points)
    # 15 values total. 3 points per value.
    value_score = correct_values * 3
    score += value_score
    feedback_parts.append(f"Data accuracy: {correct_values}/{total_values} values correct (+{value_score})")

    # 3. VLM Trajectory Verification (Max 25 points)
    # Check if the agent actually navigated the software
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    vlm_prompt = """
    Review these sequential screenshots of a user interacting with Vital Recorder software.
    I need to verify if the user is performing a chart review task.
    
    Look for:
    1. A medical waveform display (Vital Recorder interface).
    2. Evidence of timeline navigation (the vertical cursor moving to different times, or the time changing).
    3. The cursor hovering over waveforms to read values.
    
    Return JSON:
    {
        "is_vital_recorder": boolean,
        "timeline_navigation_visible": boolean,
        "cursor_interaction": boolean,
        "confidence": int (0-100)
    }
    """
    
    try:
        vlm_res = query_vlm(frames, vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('is_vital_recorder'): vlm_score += 10
        if parsed.get('timeline_navigation_visible'): vlm_score += 10
        if parsed.get('cursor_interaction'): vlm_score += 5
        
        score += vlm_score
        feedback_parts.append(f"VLM Verification: +{vlm_score}")
        
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Give partial credit if data is perfect, otherwise 0 for VLM
        if correct_values >= 12:
            score += 15
            feedback_parts.append("VLM skipped but data good (+15)")

    passed = score >= 70 and correct_values >= 10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }

def check_value(reported, actual, tolerance):
    """Helper to check if a value is within tolerance."""
    if str(reported).upper() == 'N/A':
        return str(actual) == 'N/A'
    if str(actual) == 'N/A':
        return False
        
    try:
        rep_val = float(reported)
        act_val = float(actual)
        return abs(rep_val - act_val) <= tolerance
    except ValueError:
        return False