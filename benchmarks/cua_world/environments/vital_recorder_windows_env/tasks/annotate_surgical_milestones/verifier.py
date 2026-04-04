#!/usr/bin/env python3
"""
Verifier for annotate_surgical_milestones task.

Verification Strategy:
1. Programmatic: Check if 'case_milestones.csv' was created and contains "Case Start" / "Case End".
2. Programmatic: Check if timestamps for these events are within reasonable ranges for Case #3.
3. VLM: Check trajectory to confirm user interaction with the Timeline/Event menu.
"""

import json
import os
import tempfile
import logging
import csv
import io
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_annotate_milestones(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # Define approximate valid windows for Case 3 (in seconds)
    # Case Start: typically 2-20 mins (120 - 1200s)
    # Case End: typically > 2 hours (7200s+)
    gt_start_min, gt_start_max = ground_truth.get('start_window_sec', [100, 1200])
    gt_end_min, gt_end_max = ground_truth.get('end_window_sec', [7000, 15000])

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Result JSON
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The PowerShell script saves to a Windows path. 
        # copy_from_env usually handles the path translation for the specific environment backend.
        # For 'dockur/windows', paths might be relative to the shared workspace or internal.
        # Assuming the env mapping handles "C:\Users\Docker\AppData\Local\Temp\task_result.json" 
        # to a path accessible by copy_from_env.
        # If the environment exposes the C: drive as a volume, we use that.
        # Standard gym-anything convention: absolute path inside guest.
        copy_from_env(r"C:\Users\Docker\AppData\Local\Temp\task_result.json", temp_json.name)
        
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ---------------------------------------------------------
    # 2. Check File Existence & Creation (30 points)
    # ---------------------------------------------------------
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 30
        feedback_parts.append("CSV file created successfully.")
    elif result.get('output_exists'):
        score += 10
        feedback_parts.append("CSV file exists but timestamp suggests it wasn't created during this task.")
    else:
        feedback_parts.append("Expected CSV file not found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # ---------------------------------------------------------
    # 3. Parse CSV Content (40 points)
    # ---------------------------------------------------------
    csv_content = result.get('csv_content_preview', "")
    found_start = False
    found_end = False
    start_time_val = -1.0
    end_time_val = -1.0

    # Vital Recorder export format usually: Time(s), EventName or similar
    # We'll look for the strings "Case Start" and "Case End" and try to extract associated numbers
    
    try:
        # Simple line-based parsing if CSV structure varies
        lines = csv_content.split('\n')
        for line in lines:
            line_lower = line.lower()
            if "case start" in line_lower:
                found_start = True
                # Try to extract timestamp (usually first column)
                try:
                    parts = line.split(',')
                    val = float(parts[0].strip())
                    start_time_val = val
                except:
                    pass
            
            if "case end" in line_lower:
                found_end = True
                try:
                    parts = line.split(',')
                    val = float(parts[0].strip())
                    end_time_val = val
                except:
                    pass
    except Exception as e:
        feedback_parts.append(f"Error parsing CSV content: {e}")

    if found_start:
        score += 20
        feedback_parts.append("'Case Start' event found.")
    else:
        feedback_parts.append("'Case Start' event MISSING.")

    if found_end:
        score += 20
        feedback_parts.append("'Case End' event found.")
    else:
        feedback_parts.append("'Case End' event MISSING.")

    # ---------------------------------------------------------
    # 4. Validate Timestamps (Logic Check) (15 points)
    # ---------------------------------------------------------
    # Check if timestamps make chronological sense
    timestamps_valid = False
    if start_time_val > 0 and end_time_val > 0:
        if start_time_val < end_time_val:
            timestamps_valid = True
            
            # Check against Ground Truth windows
            if gt_start_min <= start_time_val <= gt_start_max:
                score += 7.5
                feedback_parts.append("Start time is clinically accurate.")
            else:
                feedback_parts.append(f"Start time {start_time_val}s seems outside expected range ({gt_start_min}-{gt_start_max}s).")
                
            if gt_end_min <= end_time_val <= gt_end_max:
                score += 7.5
                feedback_parts.append("End time is clinically accurate.")
            else:
                feedback_parts.append(f"End time {end_time_val}s seems outside expected range ({gt_end_min}-{gt_end_max}s).")
        else:
            feedback_parts.append("Timestamps illogical (Start > End).")
    elif found_start and found_end:
        feedback_parts.append("Could not parse numeric timestamps.")

    # ---------------------------------------------------------
    # 5. VLM Verification (15 points)
    # ---------------------------------------------------------
    # Check if the agent actually used the UI menus
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Analyze these screenshots of Vital Recorder software. "
            "Look for: 1. A context menu or dialog box for 'Add Event' or 'Memo'. "
            "2. The text 'Case Start' or 'Case End' being typed. "
            "3. An export dialog or file save window. "
            "Does the user appear to be annotating the timeline?"
        )
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result.get('success'):
            # Heuristic scoring based on VLM text
            analysis = vlm_result.get('parsed', {}).get('analysis', '').lower()
            if "menu" in analysis or "event" in analysis or "dialog" in analysis:
                score += 15
                feedback_parts.append("VLM confirms annotation workflow.")
            else:
                score += 5  # Participation points if VLM runs but is unsure
        else:
            feedback_parts.append("VLM check failed.")
    else:
        # Fallback if no frames (shouldn't happen in real run)
        score += 0

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }