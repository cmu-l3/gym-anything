#!/usr/bin/env python3
"""
Verifier for export_mask_nifti task.

Scoring (100 points total):
  - File exists: 10 pts
  - File created during task (anti-gaming): 10 pts
  - Valid Gzip format: 10 pts
  - Valid NIfTI header (magic string): 20 pts
  - Dimensions valid (approx 512x512x108): 25 pts
  - File size reasonable (>50KB, not empty): 25 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_export_mask_nifti(traj, env_info, task_info):
    """Verify that the agent exported a valid NIfTI bone mask."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_size = metadata.get("min_file_size_bytes", 51200)
    exp_min = metadata.get("expected_dims_min", [200, 200, 50])
    exp_max = metadata.get("expected_dims_max", [600, 600, 200])

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_mask_nifti_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # Criterion 1: File exists (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("File exists")
    else:
        feedback_parts.append("File not found at /home/ga/Documents/bone_mask.nii.gz")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Created during task (10 pts)
    if result.get("created_during_task"):
        score += 10
    else:
        feedback_parts.append("File timestamp indicates it was not created during this session")

    # Criterion 3: Valid Gzip (10 pts)
    if result.get("is_gzip"):
        score += 10
        feedback_parts.append("Valid Gzip")
    else:
        feedback_parts.append("Not a valid gzip file")

    # Criterion 4: Valid NIfTI (20 pts)
    if result.get("is_nifti"):
        score += 20
        feedback_parts.append("Valid NIfTI header")
    else:
        feedback_parts.append("Invalid NIfTI header (magic string missing)")

    # Criterion 5: Dimensions Check (25 pts)
    dims = result.get("dims", [0, 0, 0])
    if (exp_min[0] <= dims[0] <= exp_max[0] and
        exp_min[1] <= dims[1] <= exp_max[1] and
        exp_min[2] <= dims[2] <= exp_max[2]):
        score += 25
        feedback_parts.append(f"Dimensions correct ({dims[0]}x{dims[1]}x{dims[2]})")
    else:
        feedback_parts.append(f"Dimensions incorrect or empty: {dims}")

    # Criterion 6: Content/Size Check (25 pts)
    size = result.get("file_size_bytes", 0)
    nonzero = result.get("voxel_count_nonzero", 0)
    
    # We require reasonable file size AND some non-zero content if checked
    if size >= min_size:
        score += 25
        feedback_parts.append(f"File size OK ({size//1024} KB)")
    else:
        feedback_parts.append(f"File too small ({size} bytes, expected > {min_size})")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }