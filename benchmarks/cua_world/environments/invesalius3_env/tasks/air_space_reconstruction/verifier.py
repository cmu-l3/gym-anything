#!/usr/bin/env python3
"""
Verifier for air_space_reconstruction task.

Scoring (100 points total):
  - STL file exists & created during task:     10 pts
  - STL is valid format:                       15 pts
  - STL has meaningful geometry (>500 tris):   20 pts
  - STL file size > 50KB:                      10 pts
  - Project file exists & created during task: 10 pts
  - Project file is valid archive:             10 pts
  - Project contains mask with Air HU range:   25 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_air_space_reconstruction(traj, env_info, task_info):
    """Verify agent created air space segmentation, model, and project."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # Load result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/air_space_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: STL Existence & Timestamp (10 pts) ---
    if result.get("stl_exists") and result.get("stl_created_during_task"):
        score += 10
        feedback_parts.append("STL file created")
    elif result.get("stl_exists"):
        feedback_parts.append("STL file exists but old (not created in this session)")
    else:
        feedback_parts.append("STL file not found")

    # --- Criterion 2: STL Validity (15 pts) ---
    if result.get("stl_valid"):
        score += 15
        feedback_parts.append("Valid STL format")
    else:
        feedback_parts.append("Invalid or corrupted STL")

    # --- Criterion 3: STL Geometry > 500 triangles (20 pts) ---
    tris = result.get("stl_triangle_count", 0)
    if tris > 500:
        score += 20
        feedback_parts.append(f"Geometry sufficient ({tris} triangles)")
    else:
        feedback_parts.append(f"Geometry too simple or empty ({tris} triangles)")

    # --- Criterion 4: STL Size > 50KB (10 pts) ---
    size_kb = result.get("stl_size_bytes", 0) / 1024
    if size_kb > 50:
        score += 10
        feedback_parts.append(f"File size OK ({size_kb:.1f} KB)")
    else:
        feedback_parts.append(f"File size too small ({size_kb:.1f} KB)")

    # --- Criterion 5: Project Existence & Timestamp (10 pts) ---
    if result.get("project_exists") and result.get("project_created_during_task"):
        score += 10
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file missing or old")

    # --- Criterion 6: Project Validity (10 pts) ---
    if result.get("project_valid"):
        score += 10
    else:
        feedback_parts.append("Invalid project file")

    # --- Criterion 7: Air Mask Threshold Verification (25 pts) ---
    # This ensures they didn't just export the default bone mask
    if result.get("air_mask_found"):
        score += 25
        feedback_parts.append("Correct Air HU threshold mask found")
    else:
        masks = result.get("mask_details", [])
        mask_info = ", ".join([f"{m['min_hu']}->{m['max_hu']}" for m in masks])
        feedback_parts.append(f"No Air mask found (Found masks: {mask_info or 'None'})")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }