#!/usr/bin/env python3
"""
Verifier for bitmap_stack_reconstruction task.

Key Verification Logic:
The task requires importing BMP images and MANUALLY setting the voxel spacing.
- Images: 108 slices.
- Correct Spacing: Z = 1.5 mm.
- Default Spacing (User error): Z = 1.0 mm (usually).
- Correct Height: 108 * 1.5 ≈ 162 mm.
- Incorrect Height: 108 * 1.0 ≈ 108 mm.

Scoring:
- File Existence & Validity: 40 pts
- Dimensional Accuracy (Z-height): 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bitmap_stack_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load metadata
    metadata = task_info.get("metadata", {})
    expected_z = metadata.get("expected_z_height_mm", 162.0)
    tolerance = metadata.get("z_height_tolerance_mm", 10.0)
    
    score = 0
    feedback_parts = []
    
    # Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Criterion 1: File Existence and Validity (40 pts)
    exists = result.get("exists", False)
    is_binary = result.get("is_binary", False)
    triangle_count = result.get("triangle_count", 0)
    created_during = result.get("created_during_task", False)
    
    if exists:
        score += 10
        if is_binary and triangle_count > 1000:
            score += 20
            feedback_parts.append("Valid binary STL created")
        else:
            feedback_parts.append("STL created but invalid or empty")
            
        if created_during:
            score += 10
            feedback_parts.append("New file generated")
        else:
            feedback_parts.append("File timestamp pre-dates task")
    else:
        feedback_parts.append("No output file found")
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Criterion 2: Dimensional Accuracy (60 pts)
    # This proves they entered the correct Z-spacing during import
    actual_z = result.get("z_height", 0.0)
    
    # Check bounds
    if abs(actual_z - expected_z) <= tolerance:
        score += 60
        feedback_parts.append(f"Dimensions correct (Height: {actual_z:.1f}mm)")
    else:
        # Check for specific failure mode (default 1.0 spacing)
        # 108 slices * 1.0 = 108mm
        if abs(actual_z - 108.0) <= tolerance:
            feedback_parts.append(f"FAILED: Height is ~108mm ({actual_z:.1f}mm). You likely accepted the default Z-spacing (1.0) instead of entering 1.5mm as requested.")
        else:
            feedback_parts.append(f"FAILED: Height incorrect ({actual_z:.1f}mm). Expected ~{expected_z}mm.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "z_height_mm": actual_z,
            "triangle_count": triangle_count
        }
    }