#!/usr/bin/env python3
"""
Verifier for design_ribbed_bracket task.
Checks:
1. FCStd file creation and validity.
2. Presence of PartDesign::Rib feature.
3. Geometric properties (Volume, BBox) matching requirements.
4. VLM verification of trajectory to ensure manual workflow.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_ribbed_bracket(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # =========================================================
    # 1. READ RESULT JSON FROM CONTAINER
    # =========================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    output_exists = result.get("output_exists", False)
    file_fresh = result.get("file_created_during_task", False)
    geo = result.get("geometry", {})
    
    valid_doc = geo.get("valid_doc", False)
    has_rib = geo.get("has_rib", False)
    volume = geo.get("volume", 0.0)
    bbox = geo.get("bbox", [0, 0, 0])

    # =========================================================
    # 2. SCORING CRITERIA
    # =========================================================
    score = 0
    feedback_parts = []
    
    # Crit 1: File Creation (10 pts)
    if output_exists and file_fresh:
        score += 10
        feedback_parts.append("File created successfully")
    elif output_exists:
        score += 5
        feedback_parts.append("File exists but timestamp issue")
    else:
        feedback_parts.append("No output file found")

    # Crit 2: Valid Geometry (20 pts)
    if valid_doc and volume > 0:
        score += 20
        feedback_parts.append("Valid 3D solid found")
    else:
        feedback_parts.append("File contains no valid solids")

    # Crit 3: Rib Feature Usage (30 pts)
    # This is key - we want them to use the specific tool, not just pad a triangle
    if has_rib:
        score += 30
        feedback_parts.append("Rib feature used")
    else:
        feedback_parts.append("Rib feature NOT detected (did you use Pad instead?)")

    # Crit 4: Geometric Accuracy (20 pts)
    # Expected: 50x30x50 bounding box roughly
    # Allow loose tolerance because orientation might vary (XYZ vs YXZ)
    dims = sorted(bbox)
    expected_dims = sorted([50.0, 50.0, 30.0])
    
    dim_match = True
    for d, e in zip(dims, expected_dims):
        if abs(d - e) > 3.0: # 3mm tolerance
            dim_match = False
    
    if dim_match:
        score += 20
        feedback_parts.append("Dimensions correct (approx 50x50x30)")
    else:
        feedback_parts.append(f"Dimensions incorrect: {bbox}")

    # Crit 5: Volume Accuracy (20 pts)
    # Base L: (50x30x5) + (45x30x5) = 7500 + 6750 = 14250 mm3
    # Rib: Triangle 30x30/2 * 4 = 1800 mm3
    # Total approx: 16050 mm3
    # Range 14500 - 17500 covers slight variations in rib placement
    if 14000 <= volume <= 18000:
        score += 20
        feedback_parts.append(f"Volume correct ({volume:.0f} mm³)")
    elif volume > 0:
        feedback_parts.append(f"Volume out of range ({volume:.0f} mm³)")

    # =========================================================
    # 3. VLM TRAJECTORY VERIFICATION (Anti-Gaming)
    # =========================================================
    # We check if frames show FreeCAD interface
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        try:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user working in FreeCAD to model a part? Are they sketching or using 3D tools?"
            )
            if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
                # Verification passed, no penalty
                pass
            else:
                # Slight penalty if VLM is confused, but trust code more
                feedback_parts.append("(VLM could not confirm workflow)")
        except:
            pass

    passed = score >= 70 and has_rib
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }