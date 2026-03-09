#!/usr/bin/env python3
"""
Verifier for export_hemicranium_model task.

Scoring (100 points total):
  - File Existence (10 pts)
  - Valid STL Format (10 pts)
  - Triangle Count > 10,000 (20 pts)
  - Hemispheric Crop (40 pts): Ratio of Width/Length < 0.60
  - Spatial Integrity (20 pts): Length > 120mm & Height > 100mm (ensures not over-cropped)

Pass Threshold: 80 points (Must achieve the Hemispheric Crop criteria).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_export_hemicranium_model(traj, env_info, task_info):
    """Verify the agent exported a valid left hemicranium STL."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_triangles = metadata.get("min_triangle_count", 10000)
    max_ratio = metadata.get("max_width_length_ratio", 0.60)
    min_length = metadata.get("min_length_mm", 120.0)
    min_height = metadata.get("min_height_mm", 100.0)

    score = 0
    feedback_parts = []

    # Retrieve result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_hemicranium_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # 1. File Existence (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("File exists")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Valid STL (10 pts)
    if result.get("is_valid_stl"):
        score += 10
        feedback_parts.append("Valid STL")
    else:
        feedback_parts.append("Invalid STL format")
        # Cannot verify geometry if invalid
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Content Validity / Triangle Count (20 pts)
    tri_count = result.get("triangle_count", 0)
    if tri_count >= min_triangles:
        score += 20
        feedback_parts.append(f"Good detail ({tri_count} triangles)")
    else:
        feedback_parts.append(f"Mesh too sparse ({tri_count} < {min_triangles})")

    # 4. Hemispheric Crop (40 pts)
    # The bounding box ratio is the key differentiator between full skull (ratio ~0.8) and hemi (ratio ~0.4)
    # We used sorted dimensions in export script, so aspect_ratio = shortest / longest
    ratio = result.get("aspect_ratio_width_length", 1.0)
    
    # Handle ASCII STL case where bbox wasn't calculated (ratio 0.0 or 1.0 depending on init)
    # If is_ascii is present, we might skip this check or fail it? 
    # The task asks for binary STL implicitly via verification, but ASCII is technically valid STL.
    # However, the export script only calcs bbox for binary.
    
    if result.get("is_ascii"):
        feedback_parts.append("Warning: ASCII STL detected, could not verify geometry perfectly.")
        # Penalize slightly or manual check required. For strict auto-eval:
        score += 0 # Miss out on geometry points
    else:
        if 0.1 < ratio < max_ratio:
            score += 40
            feedback_parts.append(f"Hemicranium shape confirmed (Ratio {ratio:.2f})")
        else:
            feedback_parts.append(f"Shape incorrect (Ratio {ratio:.2f} > {max_ratio}). Likely full skull.")

    # 5. Spatial Integrity (20 pts)
    # Ensures they didn't just export a tiny bone fragment to cheat the ratio
    # Sorted dims: dims[1] is middle, dims[2] is longest.
    # We expect Length (longest) > 120mm and Height (middle) > 100mm
    width = result.get("bbox_width", 0)
    length = result.get("bbox_length", 0)
    height = result.get("bbox_height", 0)
    
    dims = sorted([width, length, height])
    longest_dim = dims[2]
    middle_dim = dims[1]

    if longest_dim > min_length and middle_dim > min_height:
        score += 20
        feedback_parts.append("Anatomical extent preserved")
    else:
        feedback_parts.append(f"Model too small (Dims: {longest_dim:.0f}x{middle_dim:.0f}mm)")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "triangle_count": tri_count,
            "bbox_dims": [width, length, height],
            "ratio": ratio
        }
    }