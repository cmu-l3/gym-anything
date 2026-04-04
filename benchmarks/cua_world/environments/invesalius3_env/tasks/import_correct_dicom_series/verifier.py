#!/usr/bin/env python3
"""
Verifier for import_correct_dicom_series task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_correct_dicom_series(traj, env_info, task_info):
    """
    Verify the agent imported the correct volumetric series and exported a mesh.
    
    Points:
    - 20 pts: Output STL exists
    - 20 pts: Valid STL format
    - 60 pts: Triangle count > 10,000 (Proves full volume used, not scout)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    min_triangles = metadata.get('min_triangle_count', 10000)
    
    # Load Result
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
    
    # Criterion 1: File Exists (20 pts)
    if result.get("output_exists"):
        score += 20
        feedback_parts.append("STL file created")
    else:
        feedback_parts.append("STL file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid STL (20 pts)
    tri_count = result.get("triangle_count", 0)
    if tri_count > 0:
        score += 20
        feedback_parts.append("Valid STL format")
    else:
        feedback_parts.append("Invalid or empty STL file")
    
    # Criterion 3: Data Integrity / Correct Series Selection (60 pts)
    # The scout series (3 slices) would produce a very small mesh or none.
    # The full series (100+ slices) produces a large mesh.
    if tri_count >= min_triangles:
        score += 60
        feedback_parts.append(f"Correct volumetric data used ({tri_count} triangles)")
    elif tri_count > 0:
        feedback_parts.append(f"Incorrect series likely selected (only {tri_count} triangles, expected >{min_triangles})")
    
    # Check timestamps
    if not result.get("file_created_during_task", False):
        score = 0
        feedback_parts.append("Anti-gaming: File not created during task window")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "triangle_count": tri_count,
            "min_required": min_triangles
        }
    }