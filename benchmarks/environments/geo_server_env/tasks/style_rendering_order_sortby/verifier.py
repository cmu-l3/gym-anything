#!/usr/bin/env python3
"""Verifier for style_rendering_order_sortby task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_style_rendering_order(traj, env_info, task_info):
    """
    Verify that the 'cities_sorted' style was created correctly with sortBy VendorOption.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_style = metadata.get('expected_style_name', 'cities_sorted')
    expected_attribute = metadata.get('expected_attribute', 'pop_max')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/style_rendering_order_sortby_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Ignore missing nonce file if checks fail elsewhere
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Style exists (20 points)
    if result.get('style_found'):
        score += 20
        feedback_parts.append(f"Style '{expected_style}' created")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Style '{expected_style}' not found in workspace"
        }

    # 2. VendorOption exists (20 points)
    # The VendorOption is the core of this task (Painter's algorithm control)
    if result.get('has_vendor_option'):
        score += 20
        feedback_parts.append("VendorOption 'sortBy' present")
    else:
        feedback_parts.append("Missing 'sortBy' VendorOption")

    # 3. Correct Attribute and Order (20 points)
    # For large features on TOP, we want to draw small ones first.
    # Drawing order: 1. Small -> 2. Large
    # So sort order must be ASCENDING (default).
    sort_attr = result.get('sort_attribute', '')
    sort_order = result.get('sort_order', 'asc')
    
    if sort_attr == expected_attribute:
        if sort_order == 'asc':
            score += 20
            feedback_parts.append(f"Correctly sorts by '{expected_attribute}' (Ascending/Default)")
        else:
            # If they used DESC, large cities are drawn first, then covered by small ones. Incorrect.
            score += 5
            feedback_parts.append(f"Sorts by '{expected_attribute}' but order is DESCENDING (Large cities will be covered by small ones!)")
    else:
        feedback_parts.append(f"Incorrect sort attribute: '{sort_attr}' (expected '{expected_attribute}')")

    # 4. Symbolizer Configuration (20 points)
    sym_score = 0
    if result.get('has_point_symbolizer'):
        sym_score += 10
    if result.get('is_red'):
        sym_score += 5
    if result.get('is_circle'):
        sym_score += 5
    
    score += sym_score
    if sym_score == 20:
        feedback_parts.append("Symbolizer correct (Red Circle Point)")
    else:
        feedback_parts.append(f"Symbolizer issues ({sym_score}/20 pts)")

    # 5. Layer Association (20 points)
    if result.get('layer_associated'):
        score += 20
        feedback_parts.append("Style associated with layer")
    else:
        feedback_parts.append("Style NOT associated with layer")

    # Anti-gaming: Check for GUI interaction via VLM if scores are high but logs are empty
    # If using REST API exclusively (no GUI interaction), we might deduct points or fail if instructions implied GUI
    # The instructions say "Navigate to the GeoServer web admin... to perform this task", suggesting GUI.
    gui_detected = result.get('gui_interaction_detected', False)
    
    # VLM Trajectory Check
    query_vlm = env_info.get('query_vlm')
    vlm_success = True
    
    if query_vlm and traj:
        # Sample frames
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        if frames:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user interacting with the GeoServer SLD Style editor (text area with XML/CSS code)? Answer yes or no."
            )
            if vlm_res and isinstance(vlm_res, dict) and 'yes' in str(vlm_res.get('response', '')).lower():
                gui_detected = True # Confirmed via VLM

    # If no GUI detected at all but score is perfect, flag it (but don't fail for now, just note)
    if score == 100 and not gui_detected:
        feedback_parts.append("(Note: No GUI interaction detected)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }