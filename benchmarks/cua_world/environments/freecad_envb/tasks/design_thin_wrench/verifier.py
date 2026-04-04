#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_thin_wrench(traj, env_info, task_info):
    """
    Verifies the FreeCAD wrench design task.
    Checks:
    1. File creation
    2. Solid geometry existence
    3. Correct thickness (2mm)
    4. Correct jaw gap (15mm)
    """
    
    # 1. Retrieve Result JSON from Environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Scoring Criteria
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (10 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File 'cone_wrench.FCStd' created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found or not created during task."}

    # Criterion 2: Valid Solid (20 pts)
    geo = result.get("geometry", {})
    if geo.get("valid_solid"):
        score += 20
        feedback.append("Valid 3D solid found.")
    else:
        feedback.append("No valid solid shape detected in file.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion 3: Thickness (10 pts)
    # Target: 2.0mm. Allow strict tolerance for precise extrusion.
    bbox_z = geo.get("bbox_z", 0)
    if 1.9 <= bbox_z <= 2.1:
        score += 10
        feedback.append(f"Thickness correct ({bbox_z:.2f}mm).")
    else:
        feedback.append(f"Incorrect thickness: {bbox_z:.2f}mm (Target: 2.0mm).")

    # Criterion 4: Jaw Gap (40 pts)
    # Target: 15.0mm.
    jaw_found = geo.get("jaw_gap_found", False)
    measured_gap = geo.get("measured_gap", 0)
    
    if jaw_found and (14.8 <= measured_gap <= 15.2):
        score += 40
        feedback.append(f"Jaw gap accurate ({measured_gap:.2f}mm).")
    elif jaw_found:
        score += 20
        feedback.append(f"Jaw gap found but out of tolerance ({measured_gap:.2f}mm).")
    else:
        feedback.append("Could not identify a 15mm parallel jaw opening.")

    # Criterion 5: Volume Check (20 pts)
    # Estimated Volume ~2900 mm3. Range 2500-3500 covers variations in handle length/head shape.
    vol = geo.get("volume", 0)
    if 2000 <= vol <= 4000:
        score += 20
        feedback.append(f"Volume within reasonable range ({vol:.0f} mm3).")
    else:
        feedback.append(f"Volume seems incorrect ({vol:.0f} mm3) - check dimensions.")

    # Final Pass Check
    # Passing requires finding the jaw gap and getting the thickness right
    passed = (score >= 70) and jaw_found and (1.9 <= bbox_z <= 2.1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }