#!/usr/bin/env python3
"""
Verifier for Biomechanics Gait Viz Task.

Criteria:
1. File 'gait_viz.ggb' exists and created during task. (20 pts)
2. Data Import: At least 2 lists detected in the project (indicating Hip/Knee data). (20 pts)
3. Controller: A slider is present to control animation. (15 pts)
4. Dynamic Linkage: The 'Element' command is used, linking geometry to lists. (25 pts)
5. Geometry: Sufficient points (>3) and segments (>1) for a leg model. (20 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_biomechanics_gait_viz(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify File Existence & Anti-Gaming (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback.append("Project file created successfully.")
    elif result.get("file_exists"):
        score += 5
        feedback.append("Project file exists but timestamp is invalid (pre-existing?).")
    else:
        feedback.append("Project file 'gait_viz.ggb' not found.")

    # 3. Verify Data Import (Lists) (20 pts)
    lists_count = result.get("lists_count", 0)
    if lists_count >= 2:
        score += 20
        feedback.append(f"Data imported: {lists_count} lists found.")
    elif lists_count == 1:
        score += 10
        feedback.append("Partial data import: Only 1 list found.")
    else:
        feedback.append("No data lists found. Did you import the CSV?")

    # 4. Verify Slider (15 pts)
    if result.get("slider_found"):
        score += 15
        feedback.append("Animation slider detected.")
    else:
        feedback.append("No slider found. Animation requires a slider.")

    # 5. Verify Dynamic Linkage (Element command) (25 pts)
    # This is the core 'Hard' part: using Element(list, slider)
    if result.get("element_command_used"):
        score += 25
        feedback.append("Dynamic data linkage ('Element' command) detected.")
    else:
        feedback.append("The 'Element' command was not found. Geometry may not be linked to data.")

    # 6. Verify Geometry (20 pts)
    # Expecting H, K, A (3 points) and 2 segments
    points = result.get("points_count", 0)
    segments = result.get("segments_count", 0)
    
    if points >= 3 and segments >= 2:
        score += 20
        feedback.append(f"Leg model structure valid ({points} pts, {segments} segments).")
    elif points >= 3:
        score += 10
        feedback.append("Points found but segments missing.")
    else:
        feedback.append("Insufficient geometry for leg model.")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }