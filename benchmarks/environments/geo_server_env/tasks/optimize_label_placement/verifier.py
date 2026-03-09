#!/usr/bin/env python3
"""Verifier for optimize_label_placement task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_optimize_label_placement(traj, env_info, task_info):
    """
    Verify that the 'optimized_places' style was created with correct VendorOptions
    and applied to the populated places layer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_style = metadata.get('expected_style_name', 'optimized_places')
    expected_opts = metadata.get('expected_vendor_options', {})

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/optimize_label_placement_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Integrity Check
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass  # If nonce file missing in env, fail softly or handle elsewhere
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Style Exists (10 pts)
    if result.get('style_found'):
        score += 10
        feedback_parts.append(f"Style '{expected_style}' created")
    else:
        feedback_parts.append(f"Style '{expected_style}' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Vendor Options (20 pts each = 60 pts)
    detected_opts = result.get('vendor_options', {})
    
    # Check autoWrap
    val_wrap = detected_opts.get('autoWrap', '')
    if val_wrap == expected_opts.get('autoWrap'):
        score += 20
        feedback_parts.append("autoWrap correct (80)")
    else:
        feedback_parts.append(f"autoWrap mismatch (expected 80, got '{val_wrap}')")

    # Check maxDisplacement
    val_disp = detected_opts.get('maxDisplacement', '')
    if val_disp == expected_opts.get('maxDisplacement'):
        score += 20
        feedback_parts.append("maxDisplacement correct (50)")
    else:
        feedback_parts.append(f"maxDisplacement mismatch (expected 50, got '{val_disp}')")

    # Check spaceAround
    val_space = detected_opts.get('spaceAround', '')
    if val_space == expected_opts.get('spaceAround'):
        score += 20
        feedback_parts.append("spaceAround correct (10)")
    else:
        feedback_parts.append(f"spaceAround mismatch (expected 10, got '{val_space}')")

    # 3. Layer Default Style (10 pts)
    default_style = result.get('layer_default_style', '')
    # The default style might be returned as "optimized_places" or "ne:optimized_places"
    if expected_style in default_style:
        score += 10
        feedback_parts.append("Layer default style updated")
    else:
        feedback_parts.append(f"Layer default style incorrect ('{default_style}')")

    # 4. Map Image (20 pts)
    if result.get('image_exists'):
        if result.get('image_created_during_task'):
            # Check size
            if result.get('image_size', 0) > 5000: # 5KB min
                score += 20
                feedback_parts.append("Map preview image generated")
            else:
                score += 5
                feedback_parts.append("Map image exists but too small")
        else:
            feedback_parts.append("Map image existed before task start")
    else:
        feedback_parts.append("Map preview image NOT found")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }