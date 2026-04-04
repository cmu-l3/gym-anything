#!/usr/bin/env python3
"""
Verifier for dense_structure_volume_report task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dense_structure_volume_report(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created an STL file of dense structures (1500-3071 HU).
    2. Created an InVesalius project with correct mask thresholds.
    3. Reported a volume consistent with the generated mesh.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Load constraints from metadata
    metadata = task_info.get("metadata", {})
    target_min = metadata.get("target_min_hu", 1500)
    target_max = metadata.get("target_max_hu", 3071)
    # Triangle count limits for "dense only" (full skull is usually >200k)
    max_tri = metadata.get("max_triangles", 150000) 
    min_tri = metadata.get("min_triangles", 1000)

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. STL File Checks (40 points)
    if result.get("stl_exists") and result.get("stl_created_after_start"):
        score += 10
        feedback_parts.append("STL created")
        
        if result.get("stl_valid"):
            tri_count = result.get("stl_triangles", 0)
            if min_tri <= tri_count <= max_tri:
                score += 20
                feedback_parts.append(f"Geometry valid ({tri_count} triangles)")
            else:
                feedback_parts.append(f"Geometry mismatch ({tri_count} triangles - expected {min_tri}-{max_tri})")
                
            # Volume sanity check (not full skull volume)
            vol = result.get("stl_volume_ml", 0)
            if 2.0 < vol < 250.0: # Dense structures are small volume
                score += 10
                feedback_parts.append(f"Mesh volume realistic ({vol:.1f} mL)")
            else:
                feedback_parts.append(f"Mesh volume unrealistic ({vol:.1f} mL)")
        else:
            feedback_parts.append("STL invalid")
    else:
        feedback_parts.append("STL missing or old")

    # 2. Project & Mask Checks (40 points)
    if result.get("project_exists") and result.get("project_created_after_start"):
        score += 10
        
        # Check specific threshold usage
        p_min = result.get("mask_threshold_min", -1)
        p_max = result.get("mask_threshold_max", -1)
        
        # Allow slight tolerance for slider inaccuracies (+/- 50 HU)
        min_ok = abs(p_min - target_min) < 50
        max_ok = abs(p_max - target_max) < 50
        
        if min_ok and max_ok:
            score += 30
            feedback_parts.append(f"Custom threshold correct ({p_min}-{p_max})")
        else:
            feedback_parts.append(f"Threshold incorrect (Found: {p_min}-{p_max}, Expected ~{target_min}-{target_max})")
            # If they used Bone preset (226-3071)
            if abs(p_min - 226) < 50:
                feedback_parts.append("Used 'Bone' preset instead of custom range")
    else:
        feedback_parts.append("Project file missing")

    # 3. Volume Report Checks (20 points)
    if result.get("report_exists"):
        rep_vol = result.get("reported_volume_ml", 0)
        calc_vol = result.get("stl_volume_ml", 0)
        
        # Compare reported vs actual mesh volume (allow 50% variance due to mesh vs internal calculation diffs)
        if rep_vol > 0 and calc_vol > 0:
            ratio = abs(rep_vol - calc_vol) / calc_vol
            if ratio < 0.5:
                score += 20
                feedback_parts.append(f"Reported volume accurate ({rep_vol} mL)")
            else:
                score += 5 # Credit for reporting something
                feedback_parts.append(f"Reported volume mismatch (Reported: {rep_vol}, Mesh: {calc_vol:.1f})")
        else:
            feedback_parts.append("Report format invalid")
    else:
        feedback_parts.append("Report file missing")

    passed = score >= 60 and "Custom threshold correct" in "".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }