#!/usr/bin/env python3
"""
Verifier for road_cross_section task.
Verifies the creation of a civil engineering cross-section drawing in LibreCAD.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_road_cross_section(traj, env_info, task_info):
    """
    Verify road cross-section drawing.
    
    Criteria:
    1. File creation/validity (Anti-gaming timestamps).
    2. Layer structure (7 specific layers).
    3. Content (Entities on layers, text annotations, dimensions).
    4. Geometry (Bounding box size and symmetry).
    5. VLM Verification (Visual confirmation of road profile).
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract analysis data
    dxf_data = result.get("dxf_analysis", {})
    output_exists = result.get("output_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    # --- CRITERION 1: File Validity (15 pts) ---
    if output_exists and created_during and dxf_data.get("valid_dxf"):
        score += 15
        feedback_parts.append("Valid DXF created during task")
    elif output_exists:
        score += 5
        feedback_parts.append("File exists but timestamp check failed or invalid DXF")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    # --- CRITERION 2: Layer Structure (20 pts) ---
    required_layers = ["PAVEMENT", "CURB_GUTTER", "SIDEWALK", "SUBGRADE", "DIMENSIONS", "CENTERLINE", "ANNOTATIONS"]
    found_layers = dxf_data.get("layers_found", [])
    found_layers_upper = [l.upper() for l in found_layers]
    
    layers_found_count = 0
    for req in required_layers:
        if req in found_layers_upper:
            layers_found_count += 1
            
    layer_score = int((layers_found_count / len(required_layers)) * 20)
    score += layer_score
    feedback_parts.append(f"Layers found: {layers_found_count}/{len(required_layers)}")

    # --- CRITERION 3: Content & Entities (20 pts) ---
    entity_counts = dxf_data.get("entity_counts", {})
    total_entities = sum(entity_counts.values())
    
    # Check if we have entities on critical layers
    has_pavement = any(k.upper() == "PAVEMENT" and v > 0 for k, v in entity_counts.items())
    has_dims = dxf_data.get("dimension_count", 0) > 0
    
    if total_entities > 15:
        score += 10
        if has_pavement: score += 5
        if has_dims: score += 5
        feedback_parts.append(f"Drawing content: {total_entities} entities (Dims: {dxf_data.get('dimension_count', 0)})")
    else:
        feedback_parts.append("Drawing is nearly empty")

    # --- CRITERION 4: Text Annotations (15 pts) ---
    required_text_partials = ["ASPHALT", "AGGREGATE", "SIDEWALK", "CURB", "CL", "CENTERLINE"]
    found_text = " ".join(dxf_data.get("text_content", [])).upper()
    
    text_matches = 0
    for req in required_text_partials:
        if req in found_text:
            text_matches += 1
            
    if text_matches >= 3:
        score += 15
        feedback_parts.append(f"Text annotations found ({text_matches} matches)")
    elif text_matches > 0:
        score += 5
        feedback_parts.append("Some text annotations missing")
    else:
        feedback_parts.append("No required text annotations found")

    # --- CRITERION 5: Geometry Check (10 pts) ---
    bounds = dxf_data.get("bounds", {})
    min_x = bounds.get("min_x", 0)
    max_x = bounds.get("max_x", 0)
    width = max_x - min_x
    
    # Expecting width around 42 (from -21 to +21)
    if 30 <= width <= 60:
        score += 10
        feedback_parts.append(f"Geometry width reasonable ({width:.1f}')")
    elif width > 0:
        score += 2
        feedback_parts.append(f"Geometry width off ({width:.1f}')")

    # --- CRITERION 6: VLM Verification (20 pts) ---
    # Use VLM to confirm it actually looks like a road cross section
    # This prevents creating a file with random lines that satisfies programmatic checks
    final_screen = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screen:
        prompt = """
        Analyze this CAD drawing screenshot. 
        Does it show a road cross-section? 
        Look for:
        1. A central road/pavement area (crowned or flat).
        2. Curbs or edges on the sides.
        3. Sidewalks further out.
        4. Layers below the road (pavement structure).
        5. Text labels pointing to materials.
        
        Return JSON: {"is_cross_section": bool, "confidence": float, "details": str}
        """
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screen)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_cross_section", False):
                vlm_score = 20
                feedback_parts.append("VLM confirmed cross-section drawing")
            else:
                feedback_parts.append(f"VLM did not recognize cross-section: {parsed.get('details', 'Unknown')}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic score is high, assume OK
            if score >= 50:
                vlm_score = 10
                feedback_parts.append("VLM check skipped (error)")
    
    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 60) and output_exists and created_during

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }