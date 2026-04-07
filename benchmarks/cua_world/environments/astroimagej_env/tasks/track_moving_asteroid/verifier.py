#!/usr/bin/env python3
"""
Verifier for track_moving_asteroid task.

This script uses copy_from_env to read the exported JSON and the agent's CSV file.
It compares the agent's measurements against the hidden ground truth.
It also utilizes VLM verification on trajectory frames to ensure the agent
actually interacted with the AstroImageJ UI (stack controls).
"""

import os
import json
import csv
import math
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_track_asteroid(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Base checks
    file_exists = result.get('file_exists', False)
    file_created = result.get('file_created_during_task', False)

    if file_exists:
        score += 10
        feedback.append("CSV output exists")
    else:
        feedback.append("Target CSV file was not created.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if file_created:
        score += 10
        feedback.append("File created during session")
    else:
        feedback.append("Warning: File existed before task started.")

    # 2. Read Ground Truth
    gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/var/lib/app/ground_truth/asteroid_gt.json", gt_temp.name)
        with open(gt_temp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load ground truth: {e}")
        # Fallback to defaults generated in setup script if file read fails
        gt = {
            "slice1_x": 150.5, "slice1_y": 200.5,
            "slice5_x": 170.5, "slice5_y": 220.5,
            "tolerance": 4.0
        }
    finally:
        if os.path.exists(gt_temp.name):
            os.unlink(gt_temp.name)

    # 3. Read and Parse Agent's CSV
    csv_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_valid = False
    measurements = []
    
    try:
        copy_from_env("/tmp/agent_measurements.csv", csv_temp.name)
        with open(csv_temp.name, 'r') as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            
            # Find X and Y indices (AstroImageJ usually exports 'X' and 'Y')
            x_idx, y_idx = -1, -1
            for i, h in enumerate(headers):
                if h.strip().lower() == 'x':
                    x_idx = i
                elif h.strip().lower() == 'y':
                    y_idx = i
            
            if x_idx != -1 and y_idx != -1:
                for row in reader:
                    if len(row) > max(x_idx, y_idx):
                        try:
                            measurements.append({
                                'x': float(row[x_idx]),
                                'y': float(row[y_idx])
                            })
                        except ValueError:
                            pass
                
                if len(measurements) >= 2:
                    csv_valid = True
                    score += 10
                    feedback.append("Valid CSV format with multiple coordinates")
                else:
                    feedback.append(f"CSV lacks sufficient data rows (found {len(measurements)})")
            else:
                feedback.append(f"Could not find X and Y columns in CSV headers: {headers}")
    except Exception as e:
        feedback.append(f"Error parsing CSV: {e}")
    finally:
        if os.path.exists(csv_temp.name):
            os.unlink(csv_temp.name)

    # 4. Evaluate Coordinates
    slice1_accurate = False
    slice5_accurate = False
    
    if csv_valid:
        # Evaluate first measurement (Slice 1)
        m1 = measurements[0]
        dist1 = math.hypot(m1['x'] - gt['slice1_x'], m1['y'] - gt['slice1_y'])
        if dist1 <= gt['tolerance']:
            score += 25
            slice1_accurate = True
            feedback.append(f"Slice 1 accurate (err: {dist1:.1f}px)")
        else:
            feedback.append(f"Slice 1 inaccurate (err: {dist1:.1f}px)")

        # Evaluate last measurement (Slice 5)
        m_last = measurements[-1]
        dist5 = math.hypot(m_last['x'] - gt['slice5_x'], m_last['y'] - gt['slice5_y'])
        if dist5 <= gt['tolerance']:
            score += 25
            slice5_accurate = True
            feedback.append(f"Slice 5 accurate (err: {dist5:.1f}px)")
        else:
            feedback.append(f"Slice 5 inaccurate (err: {dist5:.1f}px)")

    # 5. VLM Trajectory Verification
    vlm_passed = False
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots from a session using AstroImageJ. "
            "Did the user successfully load an image sequence (multiple frames) and interact with it? "
            "Look for evidence of an image window displaying a stack (typically showing a slider at the "
            "bottom or a title like '1/5') and the Results table or Point tool being used. "
            "Reply with 'YES' if the workflow is visible, or 'NO' if the application remained empty or closed."
        )
        
        vlm_response = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_response and "YES" in vlm_response.upper():
            vlm_passed = True
            score += 20
            feedback.append("VLM confirmed visual trajectory")
        else:
            feedback.append("VLM did not verify visual interaction")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback.append("VLM verification skipped/failed")

    # Determine pass/fail
    # Requires file existence, proper formatting, and AT LEAST one accurate measurement
    passed = (score >= 60) and file_created and csv_valid and (slice1_accurate or slice5_accurate)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }