#!/usr/bin/env python3
"""
Verifier for export_skull_stl task.

Scoring (100 points total):
  - STL file created at correct path:              25 pts
  - File is a valid STL format (binary or ASCII):  25 pts
  - Triangle count > 10,000 (real geometry):       30 pts
  - File size > 200 KB (substantial mesh):         20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_export_skull_stl(traj, env_info, task_info):
    """Verify that the agent exported a valid STL skull model."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_triangles = metadata.get("min_triangle_count", 10000)
    min_size = metadata.get("min_file_size_bytes", 204800)

    score = 0
    feedback_parts = []

    # --- Criterion 1: STL file exists at the correct path ---
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_skull_stl_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    if result.get("file_exists"):
        score += 25
        feedback_parts.append("STL file created")
    else:
        feedback_parts.append("STL file not found at /home/ga/Documents/skull_model.stl")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Valid STL format ---
    if result.get("stl_valid"):
        score += 25
        fmt = "binary" if result.get("is_binary_stl") else "ASCII"
        feedback_parts.append(f"Valid {fmt} STL format")
    else:
        feedback_parts.append("File is not a valid STL (corrupt or wrong format)")

    # --- Criterion 3: Triangle count > 10,000 ---
    triangle_count = result.get("triangle_count", 0)
    if triangle_count >= min_triangles:
        score += 30
        feedback_parts.append(f"Adequate geometry: {triangle_count:,} triangles")
    else:
        feedback_parts.append(
            f"Insufficient geometry: {triangle_count:,} triangles (need >{min_triangles:,})"
        )

    # --- Criterion 4: File size > 200 KB ---
    file_size = result.get("file_size_bytes", 0)
    if file_size >= min_size:
        score += 20
        feedback_parts.append(f"File size OK: {file_size // 1024} KB")
    else:
        feedback_parts.append(
            f"File too small: {file_size // 1024} KB (need >{min_size // 1024} KB)"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
