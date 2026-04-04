#!/usr/bin/env python3
"""
Verifier for Newton's Method Root Visualization task.
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_newtons_method_root_viz(traj, env_info, task_info):
    """
    Verifies that the agent constructed Newton's method visualization correctly.
    
    Criteria:
    1. File creation (valid .ggb created during task).
    2. Correct function definition (x^3 - 2x - 5).
    3. Derivative usage.
    4. Geometric construction: Tangent lines used (at least 2 iterations).
    5. Mathematical accuracy: Points exist near expected iteration values:
       x0=3, x1=2.36, x2=2.127, x3=2.095.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # 2. Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score Calculation
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Anti-Gaming (15 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 15
        feedback.append("File created successfully.")
    elif result.get("file_found"):
        score += 5
        feedback.append("File found but timestamp suggests it wasn't created during this task.")
    else:
        feedback.append("No saved file found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Function Definition (20 pts)
    if result.get("has_cubic_function"):
        score += 20
        feedback.append("Function x^3 - 2x - 5 defined.")
    else:
        feedback.append("Correct cubic function not found in file.")

    # Criterion 3: Derivative (15 pts)
    if result.get("has_derivative"):
        score += 15
        feedback.append("Derivative calculated.")
    else:
        feedback.append("Derivative command not found.")

    # Criterion 4: Tangent Lines (Geometric Construction) (20 pts)
    tangents = result.get("tangent_count", 0)
    if tangents >= 3:
        score += 20
        feedback.append(f"Excellent: {tangents} tangent lines found.")
    elif tangents >= 1:
        score += 10
        feedback.append(f"Partial: {tangents} tangent line(s) found (expected 3+).")
    else:
        feedback.append("No Tangent commands found.")

    # Criterion 5: Iteration Values (Mathematical Accuracy) (20 pts)
    # Expected: 2.36, 2.127, 2.095
    points = result.get("iteration_points_found", [])
    expected_x = [2.36, 2.127, 2.094]
    found_iterations = 0
    
    for target in expected_x:
        # Check if any point in the file is close to target
        if any(math.isclose(p, target, abs_tol=0.05) for p in points):
            found_iterations += 1
            
    if found_iterations >= 3:
        score += 20
        feedback.append("All iteration points found accurately.")
    elif found_iterations >= 1:
        score += 10 * found_iterations
        feedback.append(f"Found {found_iterations}/3 expected iteration points.")
    else:
        feedback.append("Iteration points (2.36, 2.13, 2.09) not found in construction.")

    # Criterion 6: Annotation (10 pts)
    if result.get("has_annotation"):
        score += 10
        feedback.append("Annotation present.")

    # 4. Final Verdict
    # Threshold 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }