#!/usr/bin/env python3
"""
Verifier for export_model_and_picture task.

Scoring (100 points total):
  - OBJ file exists at correct path:                    20 pts
  - OBJ is a valid Wavefront file (has vertex lines):   20 pts
  - OBJ has >= 1,000 vertices (real geometry):          20 pts
  - PNG file exists at correct path:                    20 pts
  - PNG is a valid PNG image (magic bytes correct):     20 pts

Pass threshold: 70 points
  (Agent must produce at least one file correctly + partial other)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_export_model_and_picture(traj, env_info, task_info):
    """Verify that the agent exported both an OBJ surface model and a PNG screenshot."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_vertices = metadata.get("min_obj_vertices", 1000)
    min_png_size = metadata.get("min_png_size_bytes", 51200)

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_model_and_picture_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: OBJ file exists ---
    try:
        if result.get("obj_exists"):
            score += 20
            feedback_parts.append("OBJ file created")
        else:
            feedback_parts.append("OBJ file not found at /home/ga/Documents/skull_surface.obj")
    except Exception as e:
        feedback_parts.append(f"OBJ check error: {e}")

    # --- Criterion 2: OBJ is a valid Wavefront file ---
    try:
        if result.get("obj_valid"):
            score += 20
            feedback_parts.append("Valid OBJ format")
        else:
            feedback_parts.append("OBJ file is not a valid Wavefront OBJ (no vertex lines)")
    except Exception as e:
        feedback_parts.append(f"OBJ validation error: {e}")

    # --- Criterion 3: OBJ has >= 1000 vertices ---
    try:
        vertex_count = result.get("obj_vertex_count", 0)
        if vertex_count >= min_vertices:
            score += 20
            feedback_parts.append(f"OBJ has {vertex_count:,} vertices")
        else:
            feedback_parts.append(
                f"OBJ too sparse: {vertex_count} vertices (need >= {min_vertices})"
            )
    except Exception as e:
        feedback_parts.append(f"OBJ vertex check error: {e}")

    # --- Criterion 4: PNG file exists ---
    try:
        if result.get("png_exists"):
            score += 20
            feedback_parts.append("PNG screenshot created")
        else:
            feedback_parts.append("PNG not found at /home/ga/Documents/surgical_view.png")
    except Exception as e:
        feedback_parts.append(f"PNG check error: {e}")

    # --- Criterion 5: PNG is valid image ---
    try:
        png_size = result.get("png_size_bytes", 0)
        if result.get("png_valid") and png_size >= min_png_size:
            score += 20
            feedback_parts.append(f"Valid PNG image ({png_size // 1024} KB)")
        elif result.get("png_valid"):
            feedback_parts.append(
                f"PNG valid but too small: {png_size // 1024} KB (need > {min_png_size // 1024} KB)"
            )
        elif result.get("png_exists"):
            feedback_parts.append("File exists but is not a valid PNG image")
    except Exception as e:
        feedback_parts.append(f"PNG validation error: {e}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
