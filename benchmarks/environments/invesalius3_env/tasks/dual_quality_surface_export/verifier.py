#!/usr/bin/env python3
"""
Verifier for dual_quality_surface_export task.

Scoring Criteria (100 points total):
1. Files Exist & Valid (30 pts):
   - skull_best.stl exists and is valid (15 pts)
   - skull_lowres.stl exists and is valid (15 pts)
2. Quality Logic (40 pts):
   - 'best' has > 5000 triangles (10 pts)
   - 'lowres' has > 5000 triangles (10 pts)
   - 'best' has MORE triangles than 'lowres' (20 pts)
3. Anti-Gaming (30 pts):
   - Files created after task start (10 pts)
   - Files are NOT identical (10 pts)
   - Significant difference ratio (>20% difference) (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dual_quality_surface_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []
    
    # Extract data
    best = result.get("best", {})
    lowres = result.get("lowres", {})
    start_time = result.get("task_start_time", 0)

    # 1. Existence and Validity
    if best.get("exists") and best.get("valid"):
        score += 15
        feedback.append("High-quality STL exists and is valid")
    else:
        feedback.append("High-quality STL missing or invalid")

    if lowres.get("exists") and lowres.get("valid"):
        score += 15
        feedback.append("Low-quality STL exists and is valid")
    else:
        feedback.append("Low-quality STL missing or invalid")

    # 2. Triangle Counts
    count_best = best.get("triangles", 0)
    count_lowres = lowres.get("triangles", 0)

    if count_best > 5000:
        score += 10
        feedback.append(f"High-quality mesh geometry sufficient ({count_best} tris)")
    else:
        feedback.append(f"High-quality mesh too simple ({count_best} tris)")

    if count_lowres > 5000:
        score += 10
        feedback.append(f"Low-quality mesh geometry sufficient ({count_lowres} tris)")
    else:
        feedback.append(f"Low-quality mesh too simple ({count_lowres} tris)")

    # 3. Quality Comparison
    if count_best > count_lowres:
        score += 20
        feedback.append("Quality distinction verified (Best > LowRes)")
    elif count_best > 0 and count_lowres > 0:
        feedback.append("FAIL: 'Best' quality file has fewer or equal triangles than 'LowRes'")
    
    # 4. Anti-Gaming Checks
    # Time check
    files_new = True
    if best.get("exists") and best.get("mtime", 0) < start_time:
        files_new = False
    if lowres.get("exists") and lowres.get("mtime", 0) < start_time:
        files_new = False
    
    if files_new and best.get("exists") and lowres.get("exists"):
        score += 10
        feedback.append("Files created during task session")
    else:
        feedback.append("Files have stale timestamps")

    # Identity check
    if best.get("hash") != lowres.get("hash"):
        score += 10
        feedback.append("Files are distinct")
    else:
        feedback.append("FAIL: Files are identical (same hash)")

    # Significant difference check (at least 20% difference)
    if count_lowres > 0 and count_best > (count_lowres * 1.2):
        score += 10
        feedback.append("Significant quality difference (>20%) observed")
    elif count_best > count_lowres:
        feedback.append("Warning: Quality difference is marginal (<20%)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }