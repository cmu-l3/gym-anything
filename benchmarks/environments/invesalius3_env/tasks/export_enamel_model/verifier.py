#!/usr/bin/env python3
"""
Verifier for export_enamel_model task.

Scoring (100 points total):
  - STL file created:                           20 pts
  - STL is valid binary format:                 10 pts
  - Volume Analysis (5k < vol < 200k mm3):      40 pts
    (Ensures it's teeth/petrous bone, not full skull which is >350k mm3)
  - Project file saved:                         10 pts
  - High density mask used (Min HU >= 1400):    20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_export_enamel_model(traj, env_info, task_info):
    """Verify isolation of enamel structures via volume and threshold checks."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_volume = metadata.get("min_volume_mm3", 5000)
    max_volume = metadata.get("max_volume_mm3", 200000)
    target_threshold = metadata.get("min_hu_threshold", 1400)

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_enamel_model_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: STL File (30 pts) ---
    if result.get("stl_exists"):
        score += 20
        feedback_parts.append("STL file created")
        if result.get("stl_valid"):
            score += 10
            feedback_parts.append("Valid binary STL")
        else:
            feedback_parts.append("Invalid STL format")
    else:
        feedback_parts.append("STL file not found")

    # --- Criterion 2: Volume Analysis (40 pts) ---
    volume = result.get("stl_volume_mm3", 0)
    if min_volume <= volume <= max_volume:
        score += 40
        feedback_parts.append(f"Volume correct for enamel/dense bone ({int(volume)} mm³)")
    else:
        if volume > max_volume:
            feedback_parts.append(f"Volume too large ({int(volume)} mm³) - likely full skull included")
        elif volume < min_volume:
            feedback_parts.append(f"Volume too small ({int(volume)} mm³) - likely empty or noise")
        else:
            feedback_parts.append("No volume calculated")

    # --- Criterion 3: Project File (10 pts) ---
    if result.get("project_exists"):
        score += 10
        feedback_parts.append("Project saved")
    else:
        feedback_parts.append("Project file not found")

    # --- Criterion 4: Mask Threshold (20 pts) ---
    mask_min = result.get("mask_min_hu")
    if result.get("high_density_mask_found"):
        score += 20
        feedback_parts.append(f"High-density mask confirmed (Min HU: {mask_min})")
    else:
        if mask_min is not None:
            feedback_parts.append(f"Mask threshold too low (Min HU: {mask_min}, required >= {target_threshold})")
        else:
            feedback_parts.append("No valid mask threshold found in project")

    # Final Check
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "volume_mm3": volume,
            "mask_min_hu": mask_min,
            "stl_triangle_count": result.get("stl_triangle_count", 0)
        }
    }