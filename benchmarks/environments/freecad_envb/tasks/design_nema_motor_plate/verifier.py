#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_nema_motor_plate(traj, env_info, task_info):
    """
    Verifies the NEMA 17 motor plate design.
    
    Criteria:
    1. File exists and was created during task.
    2. Valid FreeCAD geometry (Solid).
    3. Correct Dimensions (50x50x6mm base).
    4. Usage of 'Hole' tool (PartDesign::Hole) - Critical learning objective.
    5. Correct mass properties (Volume checks).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    # Basic Checks
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file nema_plate.FCStd not found."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it was not created during this task session."}

    # Geometry Analysis Data (computed inside container)
    geo = result.get("geometry_analysis", {})
    if not geo.get("valid_file", False):
        return {"passed": False, "score": 10, "feedback": "File exists but contains no valid solid body."}

    score = 10
    feedback = ["File saved."]

    # 1. Bounding Box Check (50x50x6) - 20 pts
    # Allow small tolerance for fillets affecting bounding box if implementation differs slightly
    bbox = geo.get("bbox", [0, 0, 0])
    # Target: 50, 50, 6
    if (49.0 <= bbox[0] <= 51.0) and (49.0 <= bbox[1] <= 51.0) and (5.9 <= bbox[2] <= 6.1):
        score += 20
        feedback.append("Base dimensions correct (50x50x6mm).")
    else:
        feedback.append(f"Incorrect dimensions: {bbox[0]:.1f}x{bbox[1]:.1f}x{bbox[2]:.1f}mm.")

    # 2. Feature Check: "Hole" Tool Usage - 30 pts
    # The task explicitly asks for the Hole tool for mounting holes.
    feature_types = geo.get("feature_types", [])
    hole_props = geo.get("hole_properties", {})
    
    if "PartDesign::Hole" in feature_types:
        score += 30
        feedback.append("Correctly used the 'Hole' tool.")
        
        # Check Hole Specs if available
        thread_size = hole_props.get("ThreadSize", "")
        if "M3" in thread_size:
            score += 15
            feedback.append("Mounting holes are M3.")
        else:
            feedback.append(f"Hole size mismatch (Found: {thread_size}, Expected: M3).")
    else:
        feedback.append("Did not use the 'Hole' tool (likely used Pocket instead).")

    # 3. Volume Check - 25 pts
    # Base: 15,000. Center hole: ~2280. Mounts: ~200. Fillets: ~120.
    # Approx target: 12,400 mm3. 
    # Range 11,000 - 14,000 covers variations in fillet implementation or hole depth assumptions.
    volume = geo.get("volume", 0)
    if 11000 <= volume <= 14000:
        score += 25
        feedback.append(f"Volume within expected range ({volume:.0f} mm³).")
    else:
        feedback.append(f"Volume incorrect ({volume:.0f} mm³). Expected ~12,400.")

    # Final Pass Determination
    # Must have used Hole tool AND got dimensions roughly right
    passed = (score >= 70) and ("PartDesign::Hole" in feature_types)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }