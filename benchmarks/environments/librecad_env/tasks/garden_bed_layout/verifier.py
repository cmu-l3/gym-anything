#!/usr/bin/env python3
"""
Verifier for garden_bed_layout task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_garden_layout(traj, env_info, task_info):
    """
    Verify the LibreCAD garden layout task.
    
    Scoring Criteria:
    1. File Creation & Validity (15 pts)
    2. Layer Organization (15 pts) - All required layers present
    3. Geometric Fidelity (45 pts) - Ellipse, circles, boundary, fountain
    4. Dimensions & Details (10 pts) - Dimensions added, lines drawn
    5. VLM Visual Verification (15 pts) - Looks like a plan view drawing
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Load Data from Container
    # ---------------------------------------------------------
    basic_res = {}
    dxf_analysis = {}
    
    # Copy basic result
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
            copy_from_env("/tmp/task_result.json", tf.name)
            with open(tf.name, 'r') as f:
                basic_res = json.load(f)
            os.unlink(tf.name)
    except Exception as e:
        logger.error(f"Failed to load task_result.json: {e}")

    # Copy analysis result
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
            copy_from_env("/tmp/dxf_analysis.json", tf.name)
            with open(tf.name, 'r') as f:
                dxf_analysis = json.load(f)
            os.unlink(tf.name)
    except Exception as e:
        logger.error(f"Failed to load dxf_analysis.json: {e}")

    # ---------------------------------------------------------
    # 2. Evaluate File Status (15 pts)
    # ---------------------------------------------------------
    if basic_res.get("file_exists") and basic_res.get("file_created_during_task"):
        if dxf_analysis.get("valid_dxf"):
            score += 15
            feedback_parts.append("Valid DXF file created")
        else:
            score += 5
            feedback_parts.append("File created but not valid DXF")
    else:
        feedback_parts.append("No valid output file created during task")
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    # ---------------------------------------------------------
    # 3. Evaluate Layers (15 pts)
    # ---------------------------------------------------------
    found_layers = set(dxf_analysis.get("layers_found", []))
    required_layers = {"BOUNDARY", "BEDS", "WALKWAYS", "FOUNTAIN", "DIMENSIONS"}
    missing = required_layers - found_layers
    
    if not missing:
        score += 15
        feedback_parts.append("All layers present")
    else:
        layer_score = int(15 * (len(found_layers) / 5))
        score += layer_score
        feedback_parts.append(f"Missing layers: {', '.join(missing)}")

    # ---------------------------------------------------------
    # 4. Evaluate Geometry (45 pts)
    # ---------------------------------------------------------
    entities = dxf_analysis.get("entities", {})
    
    # Ellipse (15 pts) - Critical Skill
    if entities.get("ellipse_valid"):
        score += 15
        feedback_parts.append("Central ellipse correct")
    else:
        feedback_parts.append("Central ellipse missing or incorrect size/loc")

    # Boundary Rect (10 pts)
    if entities.get("boundary_rect"):
        score += 10
        feedback_parts.append("Boundary rectangle correct")
    else:
        feedback_parts.append("Boundary rectangle missing/wrong size")
        
    # Fountain (5 pts)
    if entities.get("fountain_circle"):
        score += 5
        feedback_parts.append("Fountain correct")
        
    # Corner Circles (15 pts total)
    corner_count = entities.get("corner_circles", 0)
    # Cap at 4
    corner_count = min(4, corner_count)
    if corner_count == 4:
        score += 15
        feedback_parts.append("All 4 corner beds correct")
    else:
        score += int(15 * (corner_count / 4))
        feedback_parts.append(f"Found {corner_count}/4 corner beds")

    # ---------------------------------------------------------
    # 5. Evaluate Dimensions & Details (10 pts)
    # ---------------------------------------------------------
    dims = entities.get("dimension_count", 0)
    lines = entities.get("walkway_lines", 0)
    
    if dims >= 3:
        score += 5
        feedback_parts.append("Dimensions present")
    elif dims > 0:
        score += 2
        feedback_parts.append("Insufficient dimensions")
        
    if lines >= 4:
        score += 5
        feedback_parts.append("Walkway lines present")
    
    # ---------------------------------------------------------
    # 6. VLM Verification (15 pts)
    # ---------------------------------------------------------
    # Use VLM to confirm the drawing looks like a structured plan
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Does this screen show a 2D CAD drawing of a garden layout? "
        "I expect to see a rectangle containing an ellipse in the center, "
        "circles in the corners, and lines forming paths. "
        "Are these geometric shapes visible? Answer 'Yes' or 'No' and explain."
    )
    
    try:
        vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
        content = vlm_res.get("content", "").lower()
        if "yes" in content and "ellipse" in content:
            score += 15
            feedback_parts.append("VLM confirms garden layout visibility")
        elif "yes" in content:
            score += 10
            feedback_parts.append("VLM confirms drawing activity")
        else:
            feedback_parts.append("VLM did not recognize garden shapes")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Grace points if file analysis was perfect
        if score >= 70: 
            score += 15
            feedback_parts.append("VLM check skipped (error)")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # Pass threshold: 60 pts AND critical ellipse presence
    passed = (score >= 60) and entities.get("ellipse_valid", False)
    
    if not entities.get("ellipse_valid"):
        feedback_parts.append("FAILED: Critical ellipse requirement not met")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }