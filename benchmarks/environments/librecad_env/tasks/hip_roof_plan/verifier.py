#!/usr/bin/env python3
"""
Verifier for Hip Roof Plan task in LibreCAD.
Verifies geometry using pre-computed analysis from the container environment.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hip_roof_plan(traj, env_info, task_info):
    """
    Verify the L-shaped hip roof plan.
    
    Scoring:
    1. File creation & Validity (10 pts)
    2. Layer Setup (15 pts)
    3. Wall Geometry (25 pts)
    4. Roof Geometry - Valley/Ridges (30 pts)
    5. Text Annotations (10 pts)
    6. VLM Visual Confirmation (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Extract Data
    output_exists = result.get("output_exists", False)
    file_fresh = result.get("file_created_during_task", False)
    dxf_data = result.get("dxf_analysis", {})
    
    # --- Criterion 1: File Validity (10 pts) ---
    if output_exists and file_fresh and dxf_data.get("is_valid", False):
        score += 10
        feedback_parts.append("Valid DXF file created")
    else:
        feedback_parts.append("No valid DXF file created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Layer Setup (15 pts) ---
    layers = dxf_data.get("layers", [])
    required_layers = ["WALLS", "ROOF_LINES", "NOTES"]
    layers_found = [l for l in required_layers if any(l.lower() == existing.lower() for existing in layers)]
    
    if len(layers_found) == 3:
        score += 15
        feedback_parts.append("All layers found")
    elif len(layers_found) > 0:
        score += 5 * len(layers_found)
        feedback_parts.append(f"Layers found: {layers_found}")
    else:
        feedback_parts.append("Missing required layers")

    # --- Criterion 3: Wall Geometry (25 pts) ---
    # We looked for 6 specific corner points in the DXF analysis
    corners_found = dxf_data.get("wall_corners_found", 0)
    if corners_found == 6:
        score += 25
        feedback_parts.append("Wall footprint correct")
    elif corners_found >= 4:
        score += 15
        feedback_parts.append(f"Partial wall footprint ({corners_found}/6 corners)")
    else:
        feedback_parts.append(f"Wall footprint incorrect ({corners_found}/6 corners)")

    # --- Criterion 4: Roof Geometry (30 pts) ---
    # Key geometric checks: Valley line existence and Intersection point connectivity
    valley_found = dxf_data.get("valley_line_found", False)
    intersection_found = dxf_data.get("ridge_intersection_found", False)
    
    if valley_found:
        score += 15
        feedback_parts.append("Valley line correct")
    
    if intersection_found:
        score += 15
        feedback_parts.append("Ridge/Valley intersection correct")

    # --- Criterion 5: Annotations (10 pts) ---
    text_content = " ".join(dxf_data.get("text_content", [])).upper()
    if "VALLEY" in text_content and "RIDGE" in text_content:
        score += 10
        feedback_parts.append("Annotations correct")
    elif "VALLEY" in text_content or "RIDGE" in text_content:
        score += 5
        feedback_parts.append("Partial annotations")

    # --- Criterion 6: VLM Visual Check (10 pts) ---
    # Use VLM to confirm the visual appearance matches a roof plan
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    if final_screenshot:
        try:
            prompt = """
            Does this screenshot show a LibreCAD 2D drawing of an L-shaped building roof plan? 
            Look for:
            1. An L-shaped outline.
            2. Lines crossing inside the L-shape (hip/valley lines).
            3. Text labels like 'VALLEY' or 'RIDGE'.
            Return 'YES' if it looks like a technical drawing of a roof plan.
            """
            vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_res.get("success") and "YES" in vlm_res.get("parsed", {}).get("response", "").upper():
                vlm_score = 10
                feedback_parts.append("Visual verification passed")
            else:
                feedback_parts.append("Visual verification ambiguous")
        except Exception:
            pass # Fail gracefully on VLM error
    score += vlm_score

    # Final Evaluation
    passed = score >= 75 and dxf_data.get("wall_corners_found", 0) >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }