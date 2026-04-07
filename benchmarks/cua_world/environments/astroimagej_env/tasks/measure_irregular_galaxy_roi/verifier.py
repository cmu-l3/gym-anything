#!/usr/bin/env python3
"""
Verifier for Irregular Galaxy Core Photometry task.

Verification Strategy:
1. File Existence & Anti-Gaming: Check that both the CSV and ROI coordinate files were created.
2. Coordinate Validity: Parsed coordinates must have >= 6 vertices.
3. Mathematical Alignment: Calculate the theoretical polygon area using the Shoelace formula
   from the exported coordinates. It MUST closely match the Area reported in the agent's CSV.
   This prevents the agent from faking the CSV values without drawing a matching polygon.
4. Spatial Logic: The centroid of the polygon must be near the center of the image (the galaxy core).
5. Size Logic: The area must be within sensible bounds (200 - 15000 pixels).
6. VLM Check: Ensure the trajectory shows the polygon tool and measurement interface.

Pass Threshold: 70/100 points
"""

import json
import os
import tempfile
import logging
import math

logger = logging.getLogger(__name__)


def calculate_polygon_area(coords):
    """Calculate the area of a polygon using the Shoelace formula."""
    if not coords or len(coords) < 3:
        return 0.0
    n = len(coords)
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += coords[i][0] * coords[j][1]
        area -= coords[j][0] * coords[i][1]
    return abs(area) / 2.0


def calculate_polygon_centroid(coords):
    """Calculate the simple centroid (average of vertices) of a polygon."""
    if not coords:
        return 0.0, 0.0
    x = sum(c[0] for c in coords) / len(coords)
    y = sum(c[1] for c in coords) / len(coords)
    return x, y


def verify_galaxy_roi(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # 1. Retrieve the parsed JSON results from the container
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    csv_exists = result.get("csv_exists", False)
    roi_exists = result.get("roi_exists", False)
    csv_data = result.get("csv_data", {})
    roi_coords = result.get("roi_coords", [])
    image_shape = result.get("image_shape")

    # 2. Check File Existence and Timestamps (10 points)
    if csv_exists and roi_exists:
        if result.get("csv_modified_during_task") and result.get("roi_modified_during_task"):
            score += 10
            feedback.append("Both output files were successfully created during the task.")
        else:
            score += 5
            feedback.append("Files exist but timestamps indicate they may have been created prior to the task.")
    else:
        feedback.append("Missing required output files (CSV or ROI coordinates).")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 3. Coordinate Validity (15 points)
    num_vertices = len(roi_coords)
    if num_vertices >= 6:
        score += 15
        feedback.append(f"Polygon coordinates exported successfully with {num_vertices} vertices.")
    elif num_vertices >= 3:
        score += 5
        feedback.append(f"Polygon exported, but has too few vertices ({num_vertices} < 6).")
    else:
        feedback.append("Invalid or empty polygon coordinates exported.")

    # 4. Mathematical Alignment (25 points)
    # Match the Area from the CSV to the computed area of the exported coordinates
    reported_area = csv_data.get("area")
    computed_area = calculate_polygon_area(roi_coords)

    if reported_area is not None and computed_area > 0:
        # Allow up to 15% tolerance because AIJ counts physical pixels (stair-stepping) 
        # while shoelace formula uses exact geometric area.
        percent_diff = abs(reported_area - computed_area) / computed_area
        if percent_diff <= 0.15:
            score += 25
            feedback.append(f"CSV Area ({reported_area}) mathematically aligns with Polygon coordinates ({computed_area:.1f}).")
        else:
            feedback.append(f"Mismatch: CSV Area ({reported_area}) does not align with Polygon coordinates ({computed_area:.1f}).")
    else:
        feedback.append("Could not find 'Area' in the CSV or compute area from coordinates.")

    # 5. Spatial Logic and Size Constraints (25 points)
    if image_shape and len(image_shape) >= 2:
        img_h, img_w = image_shape[-2:]
        center_x, center_y = img_w / 2.0, img_h / 2.0
    else:
        # Fallback for UIT image size
        center_x, center_y = 256.0, 256.0

    if num_vertices >= 3:
        cx, cy = calculate_polygon_centroid(roi_coords)
        distance_to_center = math.hypot(cx - center_x, cy - center_y)
        
        # Core should be near the center of the image (tolerance 100 pixels)
        if distance_to_center < 100.0:
            score += 15
            feedback.append("Polygon centroid correctly targets the galaxy core.")
        else:
            feedback.append(f"Polygon is placed incorrectly (Centroid {cx:.1f},{cy:.1f} is too far from center).")

    if computed_area >= 200 and computed_area <= 15000:
        score += 10
        feedback.append("Polygon size is reasonable for the galaxy core.")
    elif computed_area > 0:
        feedback.append(f"Polygon size ({computed_area:.1f}) is out of expected bounds [200, 15000].")

    # 6. VLM Trajectory Verification (25 points)
    from gym_anything.vlm import sample_trajectory_frames
    frames = sample_trajectory_frames(traj, n=4)
    
    VLM_PROMPT = """You are evaluating an AI agent performing an image processing task in AstroImageJ.
    Task: Draw an irregular Polygon ROI around the bright central core of a galaxy and measure it.
    
    Review these sequential screenshots.
    1. Did the agent open an astronomical image (a fuzzy white galaxy on black background)?
    2. Did the agent use a polygon/irregular shape tool to draw a boundary around the galaxy's center?
    3. Did the agent open a 'Results' or 'Measurements' table with numeric data?
    
    Return JSON:
    {
      "galaxy_image_visible": true/false,
      "polygon_roi_drawn": true/false,
      "results_table_visible": true/false,
      "reasoning": "brief explanation"
    }"""
    
    vlm_success = False
    if query_vlm and frames:
        try:
            vlm_resp = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("galaxy_image_visible") and parsed.get("polygon_roi_drawn") and parsed.get("results_table_visible"):
                    score += 25
                    vlm_success = True
                    feedback.append("VLM confirms the visual workflow (image loaded, polygon drawn, results shown).")
                else:
                    feedback.append(f"VLM check failed or partial: {parsed.get('reasoning')}")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            feedback.append("VLM verification encountered an error.")

    # Determine final pass/fail
    key_criteria_met = (score >= 70) and vlm_success and csv_exists and roi_exists
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "csv_area": reported_area,
            "computed_area": computed_area,
            "vertices": num_vertices
        }
    }