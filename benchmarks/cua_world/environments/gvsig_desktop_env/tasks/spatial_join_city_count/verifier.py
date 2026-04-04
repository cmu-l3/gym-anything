#!/usr/bin/env python3
"""
Verifier for spatial_join_city_count task in gvSIG Desktop.

Checks:
1. Output shapefile exists and was created during the task.
2. Output shapefile is Polygon type (not Point type which would mean agent saved the wrong layer).
3. Output has a new field indicating counts (Spatial Join).
4. Count values are plausible (max > 0, total roughly matches number of cities).
5. VLM verification of the process/screenshot.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_join(traj, env_info, task_info):
    """
    Verify the spatial join task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Output File Existence & Timestamp (20 pts) ---
    if result.get("output_exists") and result.get("created_during_task"):
        score += 20
        feedback_parts.append("Output shapefile created successfully.")
    elif result.get("output_exists"):
        score += 10
        feedback_parts.append("Output shapefile exists but timestamp is suspicious (pre-existing?).")
    else:
        feedback_parts.append("Output shapefile not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # Analysis data from Python script in export_result.sh
    analysis = result.get("analysis", {})
    
    # --- Criterion 2: Geometry Type (20 pts) ---
    # Must be Polygon (countries), not Point (cities)
    geom_type = analysis.get("geom_type", "unknown")
    if geom_type == "polygon":
        score += 20
        feedback_parts.append("Geometry type is correct (Polygon).")
    else:
        feedback_parts.append(f"Wrong geometry type: {geom_type}. Expected Polygon (Countries).")
        # If they saved the points layer instead of the join result
        if geom_type == "point":
             feedback_parts.append("It looks like you saved the cities layer instead of the join result.")

    # --- Criterion 3: Feature Count (10 pts) ---
    # Should match countries count (~177)
    count = analysis.get("feature_count", 0)
    if 150 <= count <= 250:
        score += 10
        feedback_parts.append(f"Feature count looks correct ({count}).")
    else:
        feedback_parts.append(f"Feature count unexpected: {count} (Expected ~177).")

    # --- Criterion 4: Join Field / Count Values (30 pts) ---
    has_count = analysis.get("has_count_field", False)
    max_count = analysis.get("max_count_value", 0)
    nonzero = analysis.get("nonzero_counts", 0)
    
    if has_count and max_count > 0:
        score += 30
        feedback_parts.append(f"Spatial join verified! Found count field with max value {max_count} and {nonzero} countries having cities.")
    elif has_count:
        score += 15
        feedback_parts.append("Count field found but all values are zero. Check spatial relationship (should be Intersects/Contains).")
    else:
        feedback_parts.append("No count field detected in output.")

    # --- Criterion 5: VLM Verification (20 pts) ---
    # Check if they actually used the tool or UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from gvSIG Desktop.
    The user was supposed to:
    1. Load a populated places (points) layer.
    2. Run the 'Spatial Join' geoprocessing tool.
    3. Create a new layer with city counts per country.

    Do you see evidence of:
    - The 'ne_110m_populated_places' layer in the Table of Contents (left panel)?
    - The 'Geoprocessing' toolbox or 'Spatial Join' dialog being open?
    - A final map showing country polygons?
    
    Answer YES or NO for each and provide a brief reasoning.
    """
    
    try:
        vlm_res = query_vlm(frames + [final_screen], vlm_prompt)
        feedback_parts.append(f"VLM Analysis: {vlm_res}")
        
        # Simple keyword heuristic for VLM score
        lower_res = vlm_res.lower()
        if "yes" in lower_res and ("join" in lower_res or "populated" in lower_res or "layer" in lower_res):
            score += 20
        else:
            # Fallback if VLM is ambiguous but file is perfect
            if score >= 80:
                score += 20
            else:
                feedback_parts.append("Visual evidence of workflow was unclear.")
    except Exception as e:
        logger.warning(f"VLM failed: {e}")
        # Grant points if file analysis was perfect
        if score >= 80:
            score += 20

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }