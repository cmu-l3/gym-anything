#!/usr/bin/env python3
"""
Verifier for generate_voronoi_polygons task.

Verifies:
1. Shapefile creation (existence + timestamp)
2. Geometry type (must be Polygon/5, not Point/1)
3. Feature count (approx equal to input points)
4. VLM visual confirmation of polygon layer
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_voronoi_polygons(traj, env_info, task_info):
    """
    Verify Voronoi polygon generation.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_geom_type = metadata.get('expected_geometry_type', 5) # 5 = Polygon
    min_features = metadata.get('min_features', 200)
    max_features = metadata.get('max_features', 280)

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Programmatic Verification (Score: 70)
    analysis = result.get('analysis', {})
    score = 0
    feedback_parts = []
    
    # Check 1: File Exists & Created During Task (25 pts)
    if analysis.get('exists') and analysis.get('created_during_task'):
        score += 25
        feedback_parts.append("Output shapefile created successfully")
    elif analysis.get('exists'):
        score += 10
        feedback_parts.append("Output file exists but timestamp is old (re-used?)")
    else:
        feedback_parts.append("Output shapefile not found")
    
    # Check 2: Geometry Type (25 pts)
    geom_type = analysis.get('geometry_type')
    if geom_type == expected_geom_type:
        score += 25
        feedback_parts.append("Geometry type is Polygon (Correct)")
    elif geom_type == 1:
        feedback_parts.append("Geometry type is Point (Incorrect - looks like a copy of input)")
    elif geom_type == -1:
        pass # File didn't exist
    else:
        feedback_parts.append(f"Geometry type is {geom_type} (Expected Polygon/5)")

    # Check 3: Feature Count (20 pts)
    # Voronoi should produce 1 polygon per input point (unless points are coincident)
    count = analysis.get('feature_count', 0)
    if min_features <= count <= max_features:
        score += 20
        feedback_parts.append(f"Feature count {count} is valid (range {min_features}-{max_features})")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Feature count {count} is outside expected range")
    
    # 3. VLM Verification (Score: 30)
    # Check for visual evidence of tool usage and polygon map
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        # Prompt for VLM
        prompt = (
            "Review this sequence of gvSIG Desktop usage.\n"
            "Goal: Generate Voronoi/Thiessen polygons from points.\n"
            "1. Do you see the 'Geoprocessing' toolbox or a dialog titled 'Voronoi' or 'Thiessen' open in the intermediate frames?\n"
            "2. In the final screenshot, does the map show a tessellation of polygons (cells fitting together like a puzzle) instead of just dots?\n"
            "3. Is the layer 'voronoi_cities' (or similar) visible in the Table of Contents?\n"
            "Answer with JSON: {\"tool_used\": bool, \"polygons_visible\": bool, \"layer_in_toc\": bool}"
        )
        
        try:
            vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
            # Simple parsing of boolean indicators from VLM (assuming helper handles JSON extraction)
            # This is a stub for logic you'd normally parse carefully
            vlm_score = 0
            if isinstance(vlm_response, dict):
                if vlm_response.get("tool_used"): vlm_score += 10
                if vlm_response.get("polygons_visible"): vlm_score += 10
                if vlm_response.get("layer_in_toc"): vlm_score += 10
            else:
                # Fallback if VLM output isn't dict, just give partial credit if positive text found
                lower_resp = str(vlm_response).lower()
                if "yes" in lower_resp or "true" in lower_resp:
                    vlm_score = 20 # Conservative estimate
            
            score += vlm_score
            feedback_parts.append(f"VLM Score: {vlm_score}/30")
            
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM verification failed (no penalty)")
            # Re-normalize score if VLM fails? Or just accept programmatic score.
            # Here we just leave it.

    # 4. Final Verdict
    # Must have created file with correct geometry to pass
    critical_pass = (analysis.get('exists') and 
                     analysis.get('created_during_task') and 
                     geom_type == expected_geom_type)
    
    passed = (score >= 60) and critical_pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }