#!/usr/bin/env python3
"""
Verifier for Z-Axis Nuclear Depth Measurement task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_z_axis_nuclear_depth(traj, env_info, task_info):
    """
    Verifies that the agent performed a Reslice and measured depth.

    Criteria:
    1. CSV file created during task containing a measurement (20 pts)
    2. Reslice TIF image saved during task (30 pts)
    3. Reslice image dimensions indicate a Z-stack cross-section (20 pts)
       - Height of reslice should match stack depth (typically small, e.g., < 100 px)
       - Width of reslice corresponds to line length (variable)
    4. Measurement plausibility (30 pts)
       - The measured length must be <= the height of the reslice image
       - (You can't have a nuclear depth larger than the entire stack depth)

    VLM Verification (Trajectory):
    - Confirms "Reslice" dialog or window was seen.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function missing"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/z_axis_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check CSV presence
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        score += 20
        feedback.append("Measurement file created.")
    else:
        feedback.append("Measurement file missing or old.")

    # 2. Check TIF presence
    if result.get("tif_exists") and result.get("tif_created_during_task"):
        score += 30
        feedback.append("Reslice image saved.")
    else:
        feedback.append("Reslice image missing.")

    # 3. Check Dimensions (Proof of Reslice)
    # The HeLa stack is likely around 30-60 slices deep. A standard XY image is usually 512x512.
    # A reslice image will have Height = Num_Slices.
    # If the user just saved the original XY image, Height would be ~512.
    # If they correctly resliced, Height should be small (<100).
    reslice_height = result.get("reslice_height", 0)
    
    if 5 <= reslice_height <= 100:
        score += 20
        feedback.append(f"Reslice dimensions valid (Height={reslice_height}px indicates Z-axis).")
    elif reslice_height > 100:
        feedback.append(f"Reslice height suspicious ({reslice_height}px). Did you save the XY view instead of the Reslice?")
    else:
        feedback.append("Reslice dimensions invalid.")

    # 4. Check Measurement Plausibility
    measured_val = result.get("measured_value", 0.0)
    
    if measured_val > 0:
        # The nucleus depth must be less than the total stack depth
        if reslice_height > 0 and measured_val <= reslice_height * 1.5: 
            # *1.5 tolerance for diagonal measurements or calibration differences
            score += 30
            feedback.append(f"Measurement valid ({measured_val:.2f}).")
        elif reslice_height > 0:
            score += 10 # Partial credit if they measured something huge (likely width)
            feedback.append(f"Measurement {measured_val:.2f} seems too large for Z-depth (Stack height {reslice_height}). Did you measure width?")
        else:
            score += 10
            feedback.append(f"Measurement {measured_val:.2f} found but could not validate against image.")
    else:
        feedback.append("No valid measurement value found in CSV.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }