#!/usr/bin/env python3
"""
Verifier for dual_tissue_segmentation task.

Scoring (100 points total):
  - Project file saved at correct path:          20 pts
  - Valid InVesalius project format:             15 pts
  - At least 2 masks present in project:         25 pts
  - Bone mask present (min>=150, max>=1000 HU):  20 pts
  - Soft tissue mask present (max<=300 HU):      20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_dual_tissue_segmentation(traj, env_info, task_info):
    """Verify that the agent created two tissue masks and saved the project."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/dual_tissue_segmentation_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: Project file exists ---
    if result.get("file_exists"):
        score += 20
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append(
            "Project file not found at /home/ga/Documents/tissue_comparison.inv3"
        )
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Valid .inv3 format ---
    if result.get("valid_inv3"):
        score += 15
        feedback_parts.append("Valid InVesalius project format")
    else:
        feedback_parts.append(
            f"Invalid .inv3 format: {result.get('parse_error', 'unknown error')}"
        )

    # --- Criterion 3: At least 2 masks ---
    mask_count = result.get("mask_count", 0)
    if mask_count >= 2:
        score += 25
        feedback_parts.append(f"{mask_count} masks found in project")
    elif mask_count == 1:
        feedback_parts.append("Only 1 mask found (need 2 — bone AND soft tissue)")
    else:
        feedback_parts.append("No masks found in project")

    # --- Criterion 4: Bone mask present ---
    if result.get("has_bone_mask"):
        score += 20
        feedback_parts.append("Bone mask present (HU range appropriate for cortical bone)")
    else:
        feedback_parts.append(
            "No bone mask found (need a mask with min_HU >= 150 and max_HU >= 1000)"
        )

    # --- Criterion 5: Soft tissue mask present ---
    if result.get("has_soft_tissue_mask"):
        score += 20
        feedback_parts.append("Soft tissue mask present (max_HU <= 300)")
    else:
        feedback_parts.append(
            "No soft tissue mask found (need a mask with max_HU <= 300)"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "mask_count": result.get("mask_count", 0),
            "masks": result.get("masks", []),
        },
    }
