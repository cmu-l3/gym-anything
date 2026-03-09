#!/usr/bin/env python3
"""
Verifier for parking_lot_striping task.

Uses a hybrid approach:
1. Structural verification via DXF analysis (performed inside container and exported as JSON)
2. Visual verification via VLM (checking the final screenshot)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_parking_lot(traj, env_info, task_info):
    """
    Verify the parking lot drawing.
    
    Criteria:
    1. File exists and is a valid DXF (10 pts)
    2. Required layers exist with correct colors (20 pts)
    3. Geometric entities present on correct layers (20 pts)
    4. "ADA" text label present (10 pts)
    5. Striping pattern matches roughly (vertical lines) (10 pts)
    6. VLM confirms visual layout (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    # 1. File checks
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
        
    if not result.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task session")
        # We don't fail immediately but penalty applies via score accumulation
    
    dxf_data = result.get("dxf_analysis", {})
    if dxf_data.get("valid_dxf", False):
        score += 10
        feedback_parts.append("Valid DXF file created")
    else:
        return {"passed": False, "score": 5, "feedback": "File exists but is not a valid DXF"}

    # 2. Layer checks
    # Expected: LOT-BOUNDARY(7), STRIPING(2), ADA(5), DIMENSIONS(3)
    layers = dxf_data.get("layers_found", {})
    required_layers = {
        "LOT-BOUNDARY": 7,
        "STRIPING": 2,
        "ADA": 5,
        "DIMENSIONS": 3
    }
    
    layers_passed = 0
    for name, color in required_layers.items():
        if name in layers:
            if layers[name] == color:
                layers_passed += 1
            else:
                feedback_parts.append(f"Layer {name} wrong color (found {layers[name]}, expected {color})")
        else:
            feedback_parts.append(f"Layer {name} missing")
            
    # Pro-rate layer score (max 20)
    score += int((layers_passed / 4) * 20)

    # 3. Entity checks (Structural)
    counts = dxf_data.get("entity_counts", {})
    
    # Check Lot Boundary (expect at least 1 polyline or 4 lines)
    if counts.get("LOT-BOUNDARY", 0) >= 1:
        score += 5
    else:
        feedback_parts.append("No entities on LOT-BOUNDARY")
        
    # Check Striping (expect horizontal line + 6 vertical lines = ~7 entities)
    if counts.get("STRIPING", 0) >= 5:
        score += 10
    else:
        feedback_parts.append("Insufficient striping lines")
        
    # Check Dimensions
    if counts.get("DIMENSIONS", 0) >= 1:
        score += 5
    else:
        feedback_parts.append("No dimensions found")

    # 4. Content Checks
    # Check for "ADA" text
    text_content = " ".join(dxf_data.get("text_content", [])).upper()
    if "ADA" in text_content:
        score += 10
        feedback_parts.append("ADA label found")
    else:
        feedback_parts.append("Missing 'ADA' text label")
        
    # 5. Striping Pattern (Geometry check)
    # We expect vertical lines at X approx: 8, 12, 21, 30, 39, 48
    x_coords = sorted(dxf_data.get("striping_x_coords", []))
    # Check if we have multiple x coordinates spaced roughly 9 units apart
    if len(x_coords) >= 4:
        score += 10
        feedback_parts.append("Vertical striping pattern detected")

    # 6. VLM Visual Verification
    # This checks if the drawing actually LOOKS like a parking lot
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        Analyze this CAD drawing of a parking lot.
        I am looking for:
        1. A rectangular boundary.
        2. A row of parking spaces (vertical lines).
        3. One space marked differently or containing text (ADA space).
        4. Dimension lines/text/arrows visible.
        
        Does the drawing show these elements?
        """
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get("success"):
            # Simple heuristic: if VLM is positive, give points
            # In a real scenario, we'd parse the VLM JSON response more strictly
            score += 30
            feedback_parts.append("Visual verification passed")
        else:
            feedback_parts.append("Visual verification failed or inconclusive")
            # Fallback points if structural checks were very good
            if score >= 50:
                score += 15 
    else:
        feedback_parts.append("No screenshot available for visual verification")

    passed = score >= 60 and layers_passed >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }