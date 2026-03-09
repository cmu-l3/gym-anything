#!/usr/bin/env python3
"""
Verifier for segment_intracranial_cavity task.

Scoring (100 points total):
  - File Creation (20 pts): Output file exists
  - File Validity (10 pts): Valid binary STL format
  - Volume Check - Minimum (20 pts): Volume > 800 mL (Ensures significant soft tissue)
  - Volume Check - Maximum (30 pts): Volume < 1900 mL (CRITICAL: Ensures scalp was removed)
  - Anatomical Accuracy (20 pts): Volume within optimal range (1100-1700 mL)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_segment_intracranial_cavity(traj, env_info, task_info):
    """Verify brain segmentation based on volume analysis."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_vol = metadata.get("min_volume_ml", 800.0)
    max_vol = metadata.get("max_volume_ml", 1900.0)
    opt_min = metadata.get("optimal_min_ml", 1100.0)
    opt_max = metadata.get("optimal_max_ml", 1700.0)

    score = 0
    feedback_parts = []
    
    # Retrieve result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/segment_intracranial_cavity_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # Criterion 1: File Existence (20 pts)
    if result.get("file_exists"):
        score += 20
        feedback_parts.append("STL file created")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Validity (10 pts)
    if result.get("is_binary_stl") and result.get("triangle_count", 0) > 1000:
        score += 10
        feedback_parts.append(f"Valid geometry ({result['triangle_count']} tris)")
    else:
        feedback_parts.append("Invalid or empty STL file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Volume Analysis
    volume = result.get("calculated_volume_ml", 0.0)
    feedback_parts.append(f"Measured Volume: {volume:.1f} mL")

    # Criterion 3: Minimum Volume (20 pts)
    # Checks if they captured the brain at all (vs just noise or bone)
    if volume > min_vol:
        score += 20
        feedback_parts.append("Volume > 800mL (Brain captured)")
    else:
        feedback_parts.append("Volume too low (Likely just bone or noise)")

    # Criterion 4: Maximum Volume (30 pts)
    # Checks if they successfully removed the scalp/skin
    # Full head volume is typically > 2500 mL
    if volume < max_vol:
        score += 30
        feedback_parts.append("Volume < 1900mL (Scalp excluded)")
    else:
        feedback_parts.append("Volume too high (Likely includes scalp/face)")

    # Criterion 5: Optimal Anatomical Range (20 pts)
    # Checks for high quality segmentation
    if opt_min <= volume <= opt_max:
        score += 20
        feedback_parts.append("Volume within optimal ICV range")
    else:
        feedback_parts.append(f"Volume outside optimal range ({opt_min}-{opt_max})")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "volume_ml": volume,
            "bounding_box": result.get("bounding_box_dims")
        }
    }