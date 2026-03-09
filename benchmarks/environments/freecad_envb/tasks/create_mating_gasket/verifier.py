#!/usr/bin/env python3
"""
Verifier for create_mating_gasket task.

This verifier combines:
1. Programmatic Geometry Check (via FreeCAD script run in export_result.sh)
   - Checks if a new body exists
   - Checks volume/thickness
   - Checks for presence of mounting holes
2. VLM Trajectory Check
   - Verifies the "External Geometry" tool was used (key workflow requirement)
   - Verifies visual quality of the model
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_mating_gasket(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. READ EXPORTED DATA
    # ================================================================
    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract geometry analysis
    geo_data = result_data.get("geometry_analysis", {})
    output_exists = result_data.get("output_exists", False)
    
    # ================================================================
    # 2. GEOMETRIC SCORING (60 points)
    # ================================================================
    score = 0
    feedback_parts = []
    
    if output_exists:
        score += 10
        feedback_parts.append("File saved successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Check for new body
    if geo_data.get("new_body_found"):
        score += 10
        feedback_parts.append("New Gasket body created.")
        
        # Check dimensions
        vol = geo_data.get("gasket_volume", 0)
        thickness = geo_data.get("gasket_thickness", 0)
        
        # Expected volume for a T8 footprint gasket (approx 40x40mm area minus holes * 2mm)
        # Rough estimate: 1500 - 4000 mm^3
        if 1000 <= vol <= 5000:
            score += 10
            feedback_parts.append(f"Volume reasonable ({vol:.1f} mm³).")
        else:
            feedback_parts.append(f"Volume incorrect ({vol:.1f} mm³).")
            
        # Target thickness 2mm +/- 0.2
        if 1.8 <= thickness <= 2.2:
            score += 10
            feedback_parts.append(f"Thickness correct ({thickness:.2f} mm).")
        else:
            feedback_parts.append(f"Thickness incorrect ({thickness:.2f} mm).")
            
        # Check holes (should be 4)
        holes = geo_data.get("holes_found", 0)
        if holes >= 4:
            score += 20
            feedback_parts.append(f"Mounting holes detected ({holes}).")
        elif holes > 0:
            score += 10
            feedback_parts.append(f"Some holes detected ({holes}), expected 4.")
        else:
            feedback_parts.append("No mounting holes detected in gasket.")
            
    else:
        feedback_parts.append("No new Gasket body found in file.")

    # ================================================================
    # 3. VLM TRAJECTORY VERIFICATION (40 points)
    # ================================================================
    # We look for usage of "External Geometry" tool icons or UI states
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        feedback_parts.append("No trajectory frames for VLM.")
    else:
        # Prompt for VLM
        prompt = """
        Review these screenshots of a FreeCAD workflow. The user should be creating a gasket that matches an existing bracket.
        
        Check for:
        1. **External Geometry Reference**: Does the user select edges of the existing 3D part while in Sketcher? (Look for purple/magenta lines or the 'External Geometry' tool icon).
        2. **Matching Shape**: Does the new sketch/solid look like it traces the footprint of the gray bracket?
        3. **Final Result**: Does the final image show TWO parts (the original bracket and a new plate/gasket underneath it)?
        
        Return JSON:
        {
            "external_geometry_used": boolean,
            "shape_matches_footprint": boolean,
            "final_assembly_visible": boolean,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("external_geometry_used"):
                score += 15
                feedback_parts.append("VLM: External geometry referencing detected.")
            if parsed.get("shape_matches_footprint"):
                score += 15
                feedback_parts.append("VLM: Shape matches bracket footprint.")
            if parsed.get("final_assembly_visible"):
                score += 10
                feedback_parts.append("VLM: Final assembly visible.")
        else:
            feedback_parts.append("VLM verification failed to run.")

    # ================================================================
    # 4. FINAL DECISION
    # ================================================================
    # Passing score: 75
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }