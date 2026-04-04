#!/usr/bin/env python3
"""
Verifier for calibrate_bone_mask_volume task.

Scoring (100 points total):
  - Project file saved at correct path: 20 pts
  - Valid InVesalius project format:    20 pts
  - Mask exists in project:             20 pts
  - Volume >= 250,000 mm3:              20 pts (Lower bound check)
  - Volume <= 350,000 mm3:              20 pts (Upper bound check)

Pass threshold: 100 points (Strict compliance required for calibration tasks)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_calibrate_bone_mask_volume(traj, env_info, task_info):
    """Verify that the agent calibrated the bone mask to the specific volume range."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Get expected values
    metadata = task_info.get("metadata", {})
    min_vol = metadata.get("min_volume_mm3", 250000)
    max_vol = metadata.get("max_volume_mm3", 350000)

    score = 0
    feedback_parts = []

    try:
        # Load result JSON
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/calibrate_volume_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # Criterion 1: File existence
    if result.get("file_exists"):
        score += 20
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Validity
    if result.get("is_valid_archive"):
        score += 20
    else:
        feedback_parts.append("Invalid project file format")

    # Criterion 3: Mask existence
    if result.get("mask_found"):
        score += 20
        feedback_parts.append("Mask data found")
    else:
        feedback_parts.append("No segmentation mask found in project")

    # Criterion 4 & 5: Volume Range
    volume = result.get("mask_volume_mm3", 0)
    feedback_parts.append(f"Measured Volume: {volume:,.0f} mm3")

    if volume >= min_vol:
        score += 20
    else:
        feedback_parts.append(f"Volume too low (Target > {min_vol:,.0f})")

    if volume <= max_vol and volume > 0:
        score += 20
    elif volume > max_vol:
        feedback_parts.append(f"Volume too high (Target < {max_vol:,.0f})")

    # Strict pass requirement
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "volume": volume,
            "voxel_count": result.get("voxel_count", 0)
        }
    }