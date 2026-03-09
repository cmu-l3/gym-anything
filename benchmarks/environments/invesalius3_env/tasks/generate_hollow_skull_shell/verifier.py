#!/usr/bin/env python3
"""
Verifier for generate_hollow_skull_shell task.

Scoring (100 points total):
1. STL Exported (20 pts): File exists.
2. Project Saved (20 pts): File exists and is valid.
3. Workflow Preservation (25 pts): Project contains >= 3 masks (Bone, Core, Result).
4. Shell Geometry (35 pts): STL triangle count > 300,000.
   - Solid bone skull ~230k triangles.
   - Hollow shell (inner+outer) ~430k triangles.
   - This robustly differentiates a simple mask from a hollow shell.

Pass Threshold: 75 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_hollow_skull_shell(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_triangles = metadata.get('min_shell_triangles', 300000)
    min_masks = metadata.get('min_masks_count', 3)

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. STL Existence (20 pts)
    if result.get('stl_exists'):
        score += 20
        feedback_parts.append("STL file exported")
    else:
        feedback_parts.append("STL file missing")

    # 2. Project Existence (20 pts)
    if result.get('proj_exists') and result.get('proj_valid'):
        score += 20
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file missing or invalid")

    # 3. Workflow Preservation (25 pts)
    # Expecting at least 3 masks: Original, Eroded/Core, Final Shell
    mask_count = result.get('proj_mask_count', 0)
    if mask_count >= min_masks:
        score += 25
        feedback_parts.append(f"Workflow preserved ({mask_count} masks)")
    else:
        feedback_parts.append(f"Incomplete workflow history ({mask_count}/{min_masks} masks)")

    # 4. Shell Geometry (35 pts)
    # The critical test: did they actually make a shell?
    tri_count = result.get('stl_triangles', 0)
    if tri_count > min_triangles:
        score += 35
        feedback_parts.append(f"Valid hollow shell geometry ({tri_count} triangles)")
    else:
        # Provide specific feedback based on count
        if tri_count > 150000:
            feedback_parts.append(f"Geometry appears solid, not hollow ({tri_count} triangles)")
        elif tri_count > 0:
            feedback_parts.append(f"Geometry too simple ({tri_count} triangles)")
        else:
            feedback_parts.append("Invalid or empty mesh")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "triangle_count": tri_count,
            "mask_count": mask_count,
            "stl_size": result.get('stl_size', 0)
        }
    }