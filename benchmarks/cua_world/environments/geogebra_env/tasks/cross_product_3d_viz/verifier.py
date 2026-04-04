#!/usr/bin/env python3
"""
Verifier for Cross Product 3D Visualization task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cross_product_3d_viz(traj, env_info, task_info):
    """
    Verify the 3D cross product task.
    
    Criteria:
    1. File created during task (15 pts)
    2. 3D Graphics View used (15 pts)
    3. Cross() command used (25 pts)
    4. At least 2 vectors present (15 pts)
    5. Parallelogram/Polygon present (15 pts)
    6. Text annotation present (15 pts)
    
    Gate: Must have created file to get any points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Criteria
    
    # Criterion 1: File created
    if result.get("file_found", False) and result.get("file_created_during_task", False):
        score += 15
        feedback_parts.append("File created successfully (+15)")
    elif result.get("file_found", False):
        feedback_parts.append("File exists but was not created during task (0/15)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task failed: No output file found at expected location."
        }

    # Criterion 2: 3D View
    if result.get("has_3d_view", False):
        score += 15
        feedback_parts.append("3D View used (+15)")
    else:
        feedback_parts.append("3D View not detected - did you switch to 3D Graphics? (0/15)")

    # Criterion 3: Cross Command (Critical)
    if result.get("has_cross_command", False):
        score += 25
        feedback_parts.append("Cross() command used (+25)")
    else:
        feedback_parts.append("Cross() command not found (0/25)")

    # Criterion 4: Vectors
    num_vecs = result.get("num_vectors", 0)
    if num_vecs >= 2:
        score += 15
        feedback_parts.append(f"{num_vecs} vectors found (+15)")
    else:
        feedback_parts.append(f"Insufficient vectors found ({num_vecs}/2) (0/15)")

    # Check correctness of result vector (Bonus validation, not explicit points but good for feedback)
    if result.get("correct_result_vector", False):
        feedback_parts.append("Result vector (2, -7, -6) verified")
    else:
        feedback_parts.append("Warning: Correct cross product vector (2, -7, -6) not found")

    # Criterion 5: Parallelogram
    if result.get("has_polygon", False):
        score += 15
        feedback_parts.append("Parallelogram/Polygon found (+15)")
    else:
        feedback_parts.append("Parallelogram not constructed (0/15)")

    # Criterion 6: Annotation
    if result.get("has_annotation", False):
        score += 15
        feedback_parts.append("Annotation found (+15)")
    else:
        feedback_parts.append("No text annotation found (0/15)")

    # Final logic
    passed = score >= 70 and result.get("has_cross_command", False)
    
    if score >= 70 and not result.get("has_cross_command", False):
        feedback_parts.append("FAILED: Score threshold met but required Cross() command missing.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }