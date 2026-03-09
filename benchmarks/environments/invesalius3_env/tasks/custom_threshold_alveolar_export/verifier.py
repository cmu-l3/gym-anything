#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_threshold_alveolar_export(traj, env_info, task_info):
    """
    Verify the custom_threshold_alveolar_export task.
    
    Criteria:
    1. STL file exists, is valid, and has reasonable geometry (>5000 triangles).
    2. Project file exists and contains a mask.
    3. The mask in the project has the specified CUSTOM threshold (150-700 HU).
       - Tolerance: +/- 20 HU to allow for slight slider inaccuracy.
       - Must NOT match standard presets (Bone=226-3071, Spongy=148-661).
    4. Files were created during the task session.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Success Criteria
    metadata = task_info.get('metadata', {})
    target_min = metadata.get('target_min_hu', 150)
    target_max = metadata.get('target_max_hu', 700)
    tolerance = metadata.get('threshold_tolerance', 20)
    min_triangles = metadata.get('min_triangle_count', 5000)

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
    feedback_parts = []
    
    # --- Criterion 1: Anti-Gaming (Files created during task) ---
    if result.get("files_created_during_task", False):
        score += 10
        feedback_parts.append("Files created during session")
    else:
        feedback_parts.append("Files NOT modified/created during session")

    # --- Criterion 2: STL Validation ---
    stl_exists = result.get("stl_exists", False)
    stl_valid = result.get("stl_valid", False)
    stl_triangles = result.get("stl_triangles", 0)

    if stl_exists and stl_valid and stl_triangles >= min_triangles:
        score += 30
        feedback_parts.append(f"Valid STL exported ({stl_triangles} triangles)")
    elif stl_exists:
        score += 10
        feedback_parts.append("STL exists but seems empty/invalid")
    else:
        feedback_parts.append("STL file missing")

    # --- Criterion 3: Project Validation & Threshold Check ---
    project_exists = result.get("project_exists", False)
    mask_thresholds = result.get("mask_thresholds", [])
    
    correct_threshold_found = False
    
    if project_exists:
        score += 10
        feedback_parts.append("Project file saved")
        
        if not mask_thresholds:
            feedback_parts.append("No masks found in project")
        else:
            # Check for the custom threshold
            for m in mask_thresholds:
                curr_min = m.get("min", -9999)
                curr_max = m.get("max", -9999)
                
                # Check strict range match with tolerance
                min_ok = abs(curr_min - target_min) <= tolerance
                max_ok = abs(curr_max - target_max) <= tolerance
                
                if min_ok and max_ok:
                    correct_threshold_found = True
                    feedback_parts.append(f"Correct custom threshold mask found ({curr_min:.0f}-{curr_max:.0f} HU)")
                    break
                
            if not correct_threshold_found:
                # Provide helpful feedback on what was found
                found_str = ", ".join([f"{m['min']:.0f}-{m['max']:.0f}" for m in mask_thresholds])
                feedback_parts.append(f"Incorrect threshold used. Found: [{found_str}]. Expected: {target_min}-{target_max} HU")
    else:
        feedback_parts.append("Project file missing")

    if correct_threshold_found:
        score += 50  # Heavy weight on doing the specific custom settings

    # Final Score Calculation
    passed = score >= 90  # Strict pass: Must have output files + correct custom threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }