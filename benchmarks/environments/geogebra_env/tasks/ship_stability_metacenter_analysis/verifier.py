#!/usr/bin/env python3
"""
Verifier for Ship Stability Metacenter Analysis Task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ship_stability(traj, env_info, task_info):
    """
    Verifies the ship stability task based on the exported JSON data.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: File created (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully.")
    else:
        feedback.append("File not found or not created during task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Hull Construction (15 pts)
    # Check if there are polygons
    if result.get("objects", {}).get("polygons", 0) >= 1:
        score += 15
        feedback.append("Hull polygon detected.")
    else:
        feedback.append("No polygons found (Hull missing).")

    # Criterion 3: Rotation Applied (20 pts)
    if result.get("rotation_found"):
        score += 20
        feedback.append("Rotation command detected.")
    else:
        feedback.append("Hull rotation not detected.")

    # Criterion 4: Submerged Poly & Intersection (20 pts)
    # We look for Intersection command or multiple polygons
    if result.get("intersect_found") and result.get("objects", {}).get("polygons", 0) >= 2:
        score += 20
        feedback.append("Submerged hull intersection detected.")
    elif result.get("objects", {}).get("polygons", 0) >= 2:
        # Partial credit if they drew it manually without Intersect command
        score += 10
        feedback.append("Multiple polygons found, assuming submerged hull created.")
    else:
        feedback.append("Submerged hull construction not clear.")

    # Criterion 5: Centroid Found (15 pts)
    if result.get("centroid_found"):
        score += 15
        feedback.append("Center of Buoyancy (Centroid) calculated.")
    else:
        feedback.append("Centroid command not found.")

    # Criterion 6: Metacenter & GM Accuracy (20 pts)
    gm_found = result.get("gm_value_found")
    unstable_text = result.get("unstable_text_found")
    
    if gm_found:
        score += 10
        feedback.append(f"GM value ({result.get('gm_value')}) is within expected range.")
    else:
        feedback.append("Correct GM value (~0.22) not found in file.")

    if unstable_text:
        score += 10
        feedback.append("Stability conclusion ('Unstable') found.")
    else:
        feedback.append("Text annotation 'Unstable' not found.")

    # 4. Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }