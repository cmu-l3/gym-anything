#!/usr/bin/env python3
import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scissor_lift_geometry(traj, env_info, task_info):
    """
    Verifies the Scissor Lift Geometry task.
    
    Criteria:
    1. File exists and valid DXF (10 pts)
    2. Correct Layers Created (15 pts)
    3. Structure Geometry (Arm lengths ~3000mm) (25 pts)
    4. Height Accuracy (Max Y ~ 3441.5mm) (30 pts)
    5. Pins placed (Count >= 8) (10 pts)
    6. Dimension entity added (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve specifications from metadata
    metadata = task_info.get('metadata', {})
    ARM_LENGTH = metadata.get('arm_length', 3000)
    ANGLE_DEG = metadata.get('angle_deg', 35)
    STAGES = metadata.get('stages', 2)
    TOLERANCE = metadata.get('tolerance_mm', 15.0) # slightly looser tolerance for manual drawing
    
    # Calculate Theoretical Height
    # Height = Stages * Arm * sin(Angle)
    THEORETICAL_HEIGHT = STAGES * ARM_LENGTH * math.sin(math.radians(ANGLE_DEG))
    logger.info(f"Target Height: {THEORETICAL_HEIGHT:.2f}")

    # Load result from container
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
    feedback = []
    
    # Extract DXF analysis data
    dxf_data = result.get('dxf_analysis', {})
    valid_dxf = dxf_data.get('valid_dxf', False)
    
    # 1. File Existence & Validity (10 pts)
    if result.get('output_exists') and result.get('file_created_during_task') and valid_dxf:
        score += 10
        feedback.append("Valid DXF file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid DXF file created during task."}

    # 2. Layers Check (15 pts)
    required_layers = {"STRUCTURE", "PINS", "PLATFORM", "DIMENSIONS"}
    found_layers = set(dxf_data.get('layers', []))
    # Case insensitive check
    found_layers_upper = {l.upper() for l in found_layers}
    
    missing_layers = required_layers - found_layers_upper
    if not missing_layers:
        score += 15
        feedback.append("All required layers found.")
    else:
        # Partial credit
        present = len(required_layers) - len(missing_layers)
        pts = int(15 * (present / 4))
        score += pts
        feedback.append(f"Missing layers: {', '.join(missing_layers)}.")

    # 3. Structure Geometry (Arms) (25 pts)
    lines = dxf_data.get('structure_lines', [])
    # Look for lines close to ARM_LENGTH
    correct_arms = [l for l in lines if abs(l - ARM_LENGTH) < TOLERANCE]
    
    # We expect at least 4 arms (2 per stage)
    if len(correct_arms) >= 4:
        score += 25
        feedback.append(f"Correct arm geometry found ({len(correct_arms)} arms of length ~{ARM_LENGTH}).")
    elif len(correct_arms) > 0:
        score += 10
        feedback.append(f"Found some arms ({len(correct_arms)}) with correct length.")
    else:
        feedback.append(f"No arms found with length {ARM_LENGTH} +/- {TOLERANCE}.")

    # 4. Height Accuracy (30 pts)
    max_y = dxf_data.get('max_y', 0)
    error = abs(max_y - THEORETICAL_HEIGHT)
    
    if error <= TOLERANCE:
        score += 30
        feedback.append(f"Total height accurate ({max_y:.1f} vs {THEORETICAL_HEIGHT:.1f}).")
    elif error <= TOLERANCE * 3:
        score += 15
        feedback.append(f"Total height approximate ({max_y:.1f}), expected {THEORETICAL_HEIGHT:.1f}.")
    else:
        feedback.append(f"Total height incorrect. Got {max_y:.1f}, expected {THEORETICAL_HEIGHT:.1f}.")

    # 5. Pins (10 pts)
    pin_diameters = dxf_data.get('pin_circles', [])
    # Filter for correct diameter (40mm)
    valid_pins = [d for d in pin_diameters if abs(d - 40) < 5.0]
    
    if len(valid_pins) >= 8:
        score += 10
        feedback.append(f"Correct number of pivot pins found ({len(valid_pins)}).")
    elif len(valid_pins) > 0:
        score += 5
        feedback.append(f"Found {len(valid_pins)} pins (expected 8).")
    else:
        feedback.append("No valid pivot pins found.")

    # 6. Dimensions (10 pts)
    dim_count = dxf_data.get('dimension_count', 0)
    if dim_count > 0:
        score += 10
        feedback.append("Dimension annotation present.")
    else:
        feedback.append("No dimensions found.")

    return {
        "passed": score >= 75 and (error <= TOLERANCE), # Must get height right to pass
        "score": score,
        "feedback": " ".join(feedback)
    }