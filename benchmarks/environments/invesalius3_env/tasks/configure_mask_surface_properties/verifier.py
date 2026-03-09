#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_configure_mask_surface_properties(traj, env_info, task_info):
    """
    Verify the InVesalius project metadata configuration.
    
    Scoring Breakdown (100 pts total):
    - 10 pts: Valid project file created
    - 15 pts: Bone mask created (valid HU thresholds)
    - 20 pts: Mask named 'Cranial Bone'
    - 15 pts: Surface created (valid geometry)
    - 20 pts: Surface named 'Skull_Model'
    - 20 pts: Surface color is Red
    
    Pass Threshold: 60 pts (Requires valid file + correct names/properties)
    """
    
    # 1. Retrieve Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # File Checks
    if result.get("file_exists") and result.get("valid_archive"):
        score += 10
        feedback_parts.append("Project file saved correctly")
    else:
        feedback_parts.append("Project file invalid or missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if not result.get("file_created_during_task"):
        feedback_parts.append("(Warning: File timestamp check failed)")

    # Mask Checks
    if result.get("mask_threshold_valid"):
        score += 15
        feedback_parts.append("Bone mask thresholds correct")
    else:
        feedback_parts.append("Mask thresholds incorrect for bone")

    if result.get("mask_name_correct"):
        score += 20
        feedback_parts.append("Mask named 'Cranial Bone'")
    else:
        found_name = result.get("details", {}).get("mask_name", "None")
        feedback_parts.append(f"Mask name mismatch (Found: '{found_name}')")

    # Surface Checks
    if result.get("surface_geometry_valid"):
        score += 15
        feedback_parts.append("Surface geometry generated")
    else:
        feedback_parts.append("Surface geometry empty/missing")

    if result.get("surface_name_correct"):
        score += 20
        feedback_parts.append("Surface named 'Skull_Model'")
    else:
        found_surf = result.get("details", {}).get("surface_name", "None")
        feedback_parts.append(f"Surface name mismatch (Found: '{found_surf}')")

    if result.get("surface_color_red"):
        score += 20
        feedback_parts.append("Surface color is Red")
    else:
        feedback_parts.append("Surface color incorrect")

    # 3. Final Determination
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }