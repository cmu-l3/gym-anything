#!/usr/bin/env python3
"""Verifier for configure_label_priority task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_label_priority(traj, env_info, task_info):
    """
    Verify that the style was created with correct priority and vendor options, 
    and assigned to the layer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_style = metadata.get('expected_style_name', 'city_labels_priority')
    expected_priority = metadata.get('expected_priority_attr', 'pop_max')
    expected_space = str(metadata.get('expected_space_around', 15))

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_label_priority_result.json", temp_file.name)
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
        # If nonce file is missing but result has nonce, that's suspicious
        if result.get('result_nonce'):
             return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce check failed"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    sld_data = result.get('sld_analysis', {})
    
    # 1. Style Created (10 pts)
    if result.get('style_found'):
        score += 10
        feedback_parts.append(f"Style '{expected_style}' exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Style not found"}

    # 2. Point Symbolizer Configured (10 pts)
    if sld_data.get('has_point_symbolizer'):
        score += 10
        feedback_parts.append("PointSymbolizer present")
    else:
        feedback_parts.append("Missing PointSymbolizer")

    # 3. Text Label Defined (10 pts)
    if sld_data.get('has_text_symbolizer'):
        if sld_data.get('label_attr') == 'name':
            score += 10
            feedback_parts.append("Label set to 'name'")
        else:
            score += 5
            feedback_parts.append(f"TextSymbolizer present but label is '{sld_data.get('label_attr')}' (expected 'name')")
    else:
        feedback_parts.append("Missing TextSymbolizer")

    # 4. Font Styling (10 pts)
    font_fam = sld_data.get('font_family', '').lower()
    font_weight = sld_data.get('font_weight', '').lower()
    font_size = str(sld_data.get('font_size', ''))
    
    font_score = 0
    if 'arial' in font_fam: font_score += 4
    if 'bold' in font_weight: font_score += 3
    if '12' in font_size: font_score += 3
    
    if font_score == 10:
        score += 10
        feedback_parts.append("Font styling correct")
    elif font_score > 0:
        score += font_score
        feedback_parts.append(f"Font styling partial ({font_score}/10)")

    # 5. Label Priority Configured (25 pts) - CRITICAL
    priority_attr = sld_data.get('priority_attr', '')
    if priority_attr == expected_priority:
        score += 25
        feedback_parts.append(f"Priority correctly set to '{expected_priority}'")
    else:
        feedback_parts.append(f"Priority NOT set correctly (found: '{priority_attr}')")

    # 6. Space Around Configured (15 pts)
    space_around = str(sld_data.get('space_around', ''))
    if space_around == expected_space:
        score += 15
        feedback_parts.append(f"VendorOption spaceAround set to {expected_space}")
    elif space_around and space_around != 'None':
        score += 5
        feedback_parts.append(f"VendorOption spaceAround set to {space_around} (expected {expected_space})")
    else:
        feedback_parts.append("VendorOption spaceAround missing")

    # 7. Layer Assigned (20 pts)
    if result.get('layer_assigned'):
        score += 20
        feedback_parts.append("Style assigned as default to layer")
    else:
        feedback_parts.append("Style NOT assigned to layer")

    # 8. VLM / Anti-Gaming Check
    # Ensure they didn't just use REST API without GUI if task implies GUI usage
    # However, for this task, we want the outcome. We'll use VLM to verify trajectory shows work.
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=5)
        if frames:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these images show a user editing a style or SLD in GeoServer? Look for XML code or style editor forms."
            )
            # If we get a definitive "No" from VLM on a "Yes" task, we might penalize
            # But here we trust the file verification primarily.
            # We will use the VLM check mainly to catch empty trajectories.
            if not vlm_res.get('success', False):
                 pass # VLM failed, ignore

    passed = score >= 60 and priority_attr == expected_priority

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }