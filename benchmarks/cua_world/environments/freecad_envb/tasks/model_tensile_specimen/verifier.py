#!/usr/bin/env python3
"""
Verifier for model_tensile_specimen task.
Validates the geometric properties of the created FreeCAD model.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_tensile_specimen(traj, env_info, task_info):
    """
    Verifies that the agent created a valid ASTM D638 tensile specimen.
    
    Criteria:
    1. File exists and was created during the task.
    2. Model contains a valid 3D solid.
    3. Bounding box matches overall dimensions (115 x 19 x 4 mm).
    4. Volume is within range (verifies "dogbone" shape vs simple block).
    5. Waist width matches specification (6 mm).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load metadata specs
    metadata = task_info.get('metadata', {})
    target_dims = metadata.get('target_dims', {'length': 115.0, 'width_max': 19.0, 'width_min': 6.0, 'thickness': 4.0})
    tol = metadata.get('tolerance_mm', 1.5)
    
    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    file_created = result.get("file_created_during_task", False)
    analysis = result.get("analysis", {})
    valid_solid = analysis.get("valid_solid", False)
    bbox_len = analysis.get("bbox_length", 0.0)
    bbox_wid = analysis.get("bbox_width", 0.0)
    bbox_thk = analysis.get("bbox_height", 0.0)
    volume = analysis.get("volume", 0.0)
    waist_width = analysis.get("waist_width", 0.0)

    # Handle bbox orientation (sort dimensions to handle rotation)
    # The task asks for alignment, but we should be robust to rotation if shape is correct
    dims = sorted([bbox_len, bbox_wid, bbox_thk])
    # Expected sorted: [4.0, 19.0, 115.0]
    expected_sorted = sorted([target_dims['thickness'], target_dims['width_max'], target_dims['length']])

    score = 0
    feedback = []

    # 3. Evaluation Logic

    # Criterion 1: File Creation (10 pts)
    if file_created:
        score += 10
    else:
        feedback.append("File not created or not saved correctly.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Solid Geometry (20 pts)
    if valid_solid:
        score += 20
    else:
        feedback.append("Model is not a valid 3D solid.")
        # If not a solid, we can't check dimensions accurately
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion 3: Bounding Box Dimensions (30 pts)
    # Check dimensions with tolerance
    dim_match = True
    for i in range(3):
        if abs(dims[i] - expected_sorted[i]) > tol:
            dim_match = False
            feedback.append(f"Dimension mismatch: Found {dims[i]:.1f}, expected {expected_sorted[i]:.1f}.")
    
    if dim_match:
        score += 30
    else:
        # Partial credit for being close (e.g. within 5mm)
        close_match = all(abs(dims[i] - expected_sorted[i]) < 5.0 for i in range(3))
        if close_match:
            score += 10
            feedback.append("Dimensions are roughly correct but outside strict tolerance.")

    # Criterion 4: Shape/Volume Check (20 pts)
    # Block volume = 115 * 19 * 4 = 8740
    # Dogbone volume is significantly less. Range 3500-5500 covers reasonable modeling variations.
    if 3500 <= volume <= 6000:
        score += 20
    else:
        feedback.append(f"Volume check failed ({volume:.0f} mm³). Shape may be a simple block or incorrect.")

    # Criterion 5: Waist/Gauge Width (20 pts)
    # This specifically checks if the center is narrower than the ends (the "dogbone" feature)
    if abs(waist_width - target_dims['width_min']) <= tol:
        score += 20
    elif waist_width > 0:
        feedback.append(f"Waist width incorrect: {waist_width:.1f} mm (Expected {target_dims['width_min']} mm).")
    else:
        feedback.append("Could not verify waist width (part might be misaligned).")

    # 4. Final Verdict
    passed = score >= 90  # High bar because dimensions are specific standards
    
    if passed:
        feedback.insert(0, "Excellent! ASTM D638 specimen modeled correctly.")
    else:
        feedback.insert(0, f"Task incomplete (Score: {score}/100).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }