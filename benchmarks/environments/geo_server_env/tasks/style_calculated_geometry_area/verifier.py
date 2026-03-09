#!/usr/bin/env python3
"""Verifier for style_calculated_geometry_area task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_style_calculated_geometry_area(traj, env_info, task_info):
    """
    Verify the creation of a dynamic style based on calculated geometry area.
    
    Scoring Criteria:
    1. Style 'area_classification' exists in 'ne' workspace (20 pts)
    2. SLD uses the 'area' function (30 pts)
    3. SLD contains the correct threshold (15.0) (10 pts)
    4. SLD contains the correct colors (Red #FF0000 and Gray #AAAAAA) (10 pts)
    5. Style is assigned to 'ne:ne_countries' (10 pts)
    6. Map image generated correctly (20 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/style_calculated_geometry_area_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Allow soft fail on nonce if file missing, but prefer strict check
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Style Existence (20 pts)
    if result.get('style_found'):
        score += 20
        feedback_parts.append(f"Style '{result.get('style_name')}' found")
    else:
        feedback_parts.append("Style NOT found")

    # 2. Area Function (30 pts) - CRITICAL
    if result.get('has_area_function'):
        score += 30
        feedback_parts.append("SLD uses 'area' function")
    else:
        feedback_parts.append("SLD missing 'area' function")

    # 3. Threshold (10 pts)
    if result.get('has_threshold'):
        score += 10
        feedback_parts.append("Threshold (15.0) found")
    else:
        feedback_parts.append("Threshold value incorrect or missing")

    # 4. Colors (10 pts)
    colors_ok = result.get('has_red') and result.get('has_gray')
    if colors_ok:
        score += 10
        feedback_parts.append("Correct colors found")
    else:
        feedback_parts.append("Colors incorrect or missing")

    # 5. Layer Assignment (10 pts)
    if result.get('layer_assigned'):
        score += 10
        feedback_parts.append("Style assigned to layer")
    else:
        feedback_parts.append(f"Style not assigned (current default: {result.get('default_style_found')})")

    # 6. Map Image (20 pts)
    img_valid = result.get('img_valid')
    img_created = result.get('img_created_during_task')
    
    if img_valid and img_created:
        score += 20
        feedback_parts.append("Map image generated successfully")
    elif img_valid:
        score += 10 # Old image?
        feedback_parts.append("Map image exists but not created during task")
    else:
        feedback_parts.append("Map image missing or invalid")

    # VLM Verification (Trajectory Check) - Independent check
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        # Sample frames to see if they were in the style editor
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        if frames:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user editing an SLD style or code in GeoServer? Look for XML code or a 'Publishing' tab."
            )
            if vlm_res.get('success'):
                # We don't change score here, but could use it to invalidate
                pass

    passed = score >= 70 and result.get('has_area_function')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }