#!/usr/bin/env python3
"""
Verifier for boolean_subtract_soft_tissue task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_boolean_subtract_soft_tissue(traj, env_info, task_info):
    """
    Verifies that the agent performed a boolean subtraction workflow.
    
    Success Criteria:
    1. STL file exists and is valid.
    2. STL has significant geometry (> 10,000 triangles).
    3. InVesalius project file exists and is valid.
    4. Project contains at least 3 masks (implying: Source A, Source B, and Result C).
       - A standard threshold workflow usually only makes 1 mask.
       - The boolean workflow requires creating 2 masks first, then generating a 3rd.
    
    Scoring:
    - STL Output: 40 pts
    - Project Output: 20 pts
    - Workflow Evidence (3+ masks): 40 pts
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # Load results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    temp_json.close()
    
    try:
        copy_from_env("/tmp/boolean_result.json", temp_json.name)
        with open(temp_json.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 1. STL Verification (40 pts)
    if result.get("stl_exists"):
        if result.get("stl_valid"):
            tri_count = result.get("stl_triangles", 0)
            if tri_count > 10000:
                score += 40
                feedback.append(f"STL exported successfully ({tri_count} triangles).")
            else:
                score += 20
                feedback.append(f"STL exists but geometry is trivial ({tri_count} triangles).")
        else:
            score += 10
            feedback.append("STL file exists but format is invalid.")
    else:
        feedback.append("Soft tissue STL file not found.")

    # 2. Project Verification (20 pts)
    if result.get("project_exists") and result.get("project_valid"):
        score += 20
        feedback.append("Project file saved successfully.")
    else:
        feedback.append("Project file missing or invalid.")

    # 3. Workflow Verification (40 pts)
    # Boolean subtraction typically implies: Wide Mask (1) + Bone Mask (2) -> Result Mask (3)
    mask_count = result.get("project_mask_count", 0)
    masks = result.get("masks", [])
    
    if mask_count >= 3:
        score += 40
        feedback.append(f"Workflow verified: {mask_count} masks found (indicates boolean operations).")
        
        # Optional: Bonus check for mask ranges (not strict scoring, just info)
        has_bone = any(m['threshold_range'][0] >= 150 for m in masks)
        has_wide = any(m['threshold_range'][0] <= 0 for m in masks)
        if has_bone and has_wide:
            feedback.append("Mask thresholds appear consistent with task (Bone + Soft Tissue).")
            
    elif mask_count == 2:
        score += 20
        feedback.append("Partial workflow: Only 2 masks found. Boolean result might be missing.")
    elif mask_count == 1:
        score += 10
        feedback.append("Only 1 mask found. Likely simple thresholding used instead of boolean subtraction.")
    else:
        feedback.append("No masks found in project.")

    # Final Check
    passed = score >= 80  # Require STL + Project + at least 2-3 masks
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }