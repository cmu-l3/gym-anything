#!/usr/bin/env python3
"""
Verifier for Surveying Resection (Three-Point Problem) task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_surveying_resection_three_point(traj, env_info, task_info):
    """
    Verify the three-point resection construction.
    
    Criteria:
    1. File created during task (10 pts)
    2. Landmarks A, B, C plotted correctly (20 pts)
    3. Construction circles/arcs present (30 pts)
    4. Solution point P found within tolerance (30 pts)
    5. Validation angles measured (10 pts)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback = []
    
    # 1. File creation (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback.append("File created successfully (+10)")
    elif result.get('file_found'):
        feedback.append("File exists but was not created during this task (0/10)")
    else:
        feedback.append("File not found (0/10)")

    # 2. Landmarks (20 pts)
    landmarks_count = result.get('landmarks_found_count', 0)
    if landmarks_count == 3:
        score += 20
        feedback.append("All 3 landmarks plotted correctly (+20)")
    else:
        partial = int((landmarks_count / 3) * 20)
        score += partial
        feedback.append(f"Landmarks plotted: {landmarks_count}/3 (+{partial})")
        missing = [k for k, v in result.get('landmarks_status', {}).items() if not v]
        if missing:
            feedback.append(f"Missing/Incorrect landmarks: {', '.join(missing)}")

    # 3. Construction Circles (30 pts)
    circles = result.get('circles_found', 0)
    if circles >= 2:
        score += 30
        feedback.append(f"Construction circles/arcs found ({circles}) (+30)")
    elif circles == 1:
        score += 15
        feedback.append("Only 1 construction circle found (+15)")
    else:
        feedback.append("No construction circles/arcs found. Must use geometric construction (0/30)")

    # 4. Solution Point P (30 pts)
    if result.get('solution_found'):
        score += 30
        coords = result.get('solution_coords', {})
        cx = coords.get('x', 0)
        cy = coords.get('y', 0)
        feedback.append(f"Solution point P found at ({cx:.2f}, {cy:.2f}) (+30)")
    else:
        feedback.append("Correct solution point P not found (0/30)")

    # 5. Validation Angles (10 pts)
    angles = result.get('angles_found', 0)
    if angles >= 2:
        score += 10
        feedback.append("Validation angle measurements present (+10)")
    elif angles == 1:
        score += 5
        feedback.append("Partial angle measurements (+5)")
    else:
        feedback.append("No angle measurements found (0/10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }