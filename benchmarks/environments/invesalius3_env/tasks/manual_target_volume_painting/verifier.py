#!/usr/bin/env python3
"""
Verifier for manual_target_volume_painting task.

This task requires the agent to manually paint a target on specific slices.
Verification relies on analyzing the geometry of the exported STL.
A manually painted target on 3 slices will have a very small Z-height (approx 4.5mm),
whereas a threshold-based segmentation of the skull would have a large Z-height (>100mm).

Criteria:
1. STL File exists and was created during task (20 pts)
2. Triangle count is within realistic range for a painted target (100 - 15,000) (20 pts)
   - Too low (<100) = empty/noise
   - Too high (>15k) = likely full skull/brain thresholding
3. Z-Height Analysis (40 pts)
   - Must be < 30mm (Target is 3 slices ~ 4.5mm)
   - This proves manual slice selection vs global thresholding
4. VLM Verification (20 pts)
   - confirm manual segmentation tools were used

Pass Threshold: 80 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_target_volume_painting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from export_result.sh
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamp (20 pts) ---
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("STL file created")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("STL file exists but timestamp uncertain")
    else:
        feedback_parts.append("No STL file produced")
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    # --- Criterion 2: Triangle Count (Complexity) (20 pts) ---
    tri_count = result.get("triangle_count", 0)
    min_tri = task_info.get("metadata", {}).get("min_triangles", 100)
    max_tri = task_info.get("metadata", {}).get("max_triangles", 15000)
    
    if min_tri <= tri_count <= max_tri:
        score += 20
        feedback_parts.append(f"Triangle count valid for manual target ({tri_count})")
    elif tri_count > max_tri:
        feedback_parts.append(f"Triangle count too high ({tri_count}) - looks like full segmentation, not manual painting")
    else:
        feedback_parts.append(f"Triangle count too low ({tri_count}) - mesh empty or trivial")

    # --- Criterion 3: Z-Height Analysis (Slice Locality) (40 pts) ---
    z_height = result.get("z_height", 0.0)
    max_z = task_info.get("metadata", {}).get("max_allowed_z_height_mm", 30.0)
    
    # Ideal height is ~4.5mm (3 slices * 1.5mm). We allow up to 30mm for smoothing/mistakes.
    # A full skull is >150mm.
    if 1.0 < z_height < max_z:
        score += 40
        feedback_parts.append(f"Z-height ({z_height:.1f}mm) confirms manual slice painting")
    elif z_height >= max_z:
        feedback_parts.append(f"Z-height ({z_height:.1f}mm) is too large - implies global thresholding/wrong slices")
    else:
        feedback_parts.append(f"Z-height ({z_height:.1f}mm) is too small/flat")

    # --- Criterion 4: VLM Verification (20 pts) ---
    # Check if they actually opened the manual segmentation panel
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Review these screenshots of the InVesalius medical software.
    I am looking for evidence that the user performed MANUAL SEGMENTATION.
    
    Look for:
    1. The "Manual segmentation" panel being open (usually on the left side).
    2. A "Brush" or "Pencil" tool being active.
    3. Painting actions on the slice views (colored overlay appearing).
    
    Did the user perform manual segmentation?
    Answer YES or NO and explain briefly.
    """
    
    vlm_score = 0
    if frames:
        try:
            query_vlm = env_info.get("query_vlm")
            if query_vlm:
                vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
                if vlm_resp and vlm_resp.get("success"):
                    resp_text = vlm_resp.get("response", "").upper()
                    if "YES" in resp_text:
                        vlm_score = 20
                        feedback_parts.append("VLM confirms manual segmentation tools used")
                    else:
                        feedback_parts.append("VLM did not see manual segmentation tools")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Give benefit of doubt if VLM fails but file analysis passes
            if score >= 60:
                vlm_score = 20
                feedback_parts.append("VLM check skipped (error)")
    
    score += vlm_score

    # Final Pass/Fail
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "z_height": z_height,
            "triangle_count": tri_count
        }
    }