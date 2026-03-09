#!/usr/bin/env python3
"""
Verifier for crop_calvarium_export task.

Scoring Logic (100 points total):
1. File Existence & Validity (25 pts)
   - File exists at correct path (10 pts)
   - File is valid binary STL (15 pts)

2. Anti-Gaming (5 pts)
   - File created/modified after task start (5 pts)

3. Geometry Verification (70 pts)
   - Triangle Count (35 pts):
     - > 3,000 (Non-trivial mesh) AND < 180,000 (Not full skull)
   - Spatial Cropping (35 pts):
     - Bounding Box Ratio (min_dim / max_dim) < 0.65
     - Rationale: A full skull is roughly spherical/cubical (ratio ~0.8-0.9).
       A cropped calvarium (skull cap) is flat/wide (ratio < 0.6).

Pass Threshold: 65 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_crop_calvarium_export(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Load metadata limits
    metadata = task_info.get("metadata", {})
    min_tris = metadata.get("min_triangles", 3000)
    max_tris = metadata.get("max_triangles", 180000)
    max_bb_ratio = metadata.get("max_bb_ratio", 0.65)

    # Fetch result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Basic File Checks (25 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("File created")
        
        if result.get("is_binary_stl"):
            score += 15
            feedback.append("Valid binary STL")
        else:
            feedback.append("Invalid or ASCII STL format")
    else:
        feedback.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Anti-Gaming (5 pts)
    if result.get("file_created_during_task"):
        score += 5
    else:
        feedback.append("Warning: File timestamp indicates pre-existing file")

    # 3. Geometry Verification (70 pts)
    tri_count = result.get("triangle_count", 0)
    bb_ratio = result.get("bounding_box_ratio", 1.0)
    dims = result.get("dims", [0, 0, 0])

    # Triangle Count Check
    if min_tris <= tri_count <= max_tris:
        score += 35
        feedback.append(f"Triangle count valid ({tri_count:,})")
    else:
        if tri_count < min_tris:
            feedback.append(f"Mesh too simple ({tri_count:,} tris < {min_tris})")
        else:
            feedback.append(f"Mesh too complex/uncropped ({tri_count:,} tris > {max_tris})")

    # Bounding Box Ratio Check
    # Full skull is roughly 1:1:1. Calvarium is flat (e.g., 1:1:0.4).
    if bb_ratio < max_bb_ratio and tri_count > 0:
        score += 35
        feedback.append(f"Cropping confirmed (Aspect Ratio: {bb_ratio:.2f})")
    elif tri_count > 0:
        feedback.append(f"Shape incorrect - likely full skull (Aspect Ratio: {bb_ratio:.2f} > {max_bb_ratio})")
        feedback.append(f"Dims: {dims[0]:.0f}x{dims[1]:.0f}x{dims[2]:.0f}")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }