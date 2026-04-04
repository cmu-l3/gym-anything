#!/usr/bin/env python3
"""
Verifier for export_negative_mold_stl task.

Scoring (100 points total):
  - STL file exists at correct path:           10 pts
  - Valid binary STL format:                   10 pts
  - Full volume exported (BBox > 400mm):       50 pts (CRITICAL)
  - Internal cavity exists (Triangles > 10k):  30 pts (CRITICAL)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_export_negative_mold(traj, env_info, task_info):
    """Verify that the agent exported a negative mold (inverted mask) STL."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_dim = metadata.get("min_dimension_mm", 400.0)
    min_tris = metadata.get("min_triangle_count", 10000)

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_negative_mold_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: File Existence (10 pts) ---
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("STL file created")
    else:
        feedback_parts.append("STL file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Valid Format (10 pts) ---
    if result.get("is_binary_stl"):
        score += 10
        feedback_parts.append("Valid binary STL")
    else:
        feedback_parts.append("Invalid or ASCII STL (task requires binary)")

    # --- Criterion 3: Full Volume Bounding Box (50 pts) ---
    # This differentiates the "Negative Mold" (full volume box) from the "Skull" (smaller object)
    x_ext = result.get("bbox_x_extent", 0)
    y_ext = result.get("bbox_y_extent", 0)
    if x_ext > min_dim or y_ext > min_dim:
        score += 50
        feedback_parts.append(f"Correct volume dimensions (Box width: {x_ext:.1f}mm)")
    else:
        feedback_parts.append(
            f"Dimensions too small ({x_ext:.1f}mm). Likely exported positive skull instead of negative mold."
        )

    # --- Criterion 4: Complexity / Internal Cavity (30 pts) ---
    # Differentiates the "Mold" (complex) from a "Solid Cube" (simple)
    tris = result.get("triangle_count", 0)
    if tris > min_tris:
        score += 30
        feedback_parts.append(f"High detail mesh ({tris} triangles)")
    else:
        feedback_parts.append(
            f"Mesh too simple ({tris} triangles). Did you create the surface from the mask correctly?"
        )

    passed = score >= 90  # Strict pass: must be negative mold AND valid mesh
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "bbox_x": x_ext,
            "triangles": tris,
        },
    }