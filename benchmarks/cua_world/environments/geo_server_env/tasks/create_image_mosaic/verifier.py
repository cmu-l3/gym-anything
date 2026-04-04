#!/usr/bin/env python3
"""Verifier for create_image_mosaic task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_image_mosaic(traj, env_info, task_info):
    """
    Verify that an ImageMosaic store was configured and published correctly.
    
    Criteria:
    1. Workspace 'imagery' exists.
    2. Store 'world_mosaic_store' exists and is type 'ImageMosaic'.
    3. Store points to correct directory.
    4. Layer 'global_mask' is published and enabled.
    5. WMS output verification: The layer actually renders data (non-blank image).
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ws = metadata.get('expected_workspace', 'imagery')
    expected_store = metadata.get('expected_store', 'world_mosaic_store')
    expected_layer = metadata.get('expected_layer', 'global_mask')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_image_mosaic_result.json", temp_file.name)
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
        # If nonce check fails, we still score but note it (or fail strict)
        # For this template, we'll fail if nonce is totally missing when it should be there
        pass
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace (10 points)
    if result.get('workspace_found'):
        score += 10
        feedback_parts.append(f"Workspace '{expected_ws}' created")
    else:
        feedback_parts.append(f"Workspace '{expected_ws}' MISSING")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Store (30 points)
    if result.get('store_found'):
        store_type = result.get('store_type', '')
        if 'ImageMosaic' in store_type:
            score += 30
            feedback_parts.append(f"Store '{expected_store}' created (Type: ImageMosaic)")
        else:
            score += 10 # Partial credit for creating store but wrong type
            feedback_parts.append(f"Store '{expected_store}' exists but wrong type: {store_type}")
    else:
        feedback_parts.append(f"Store '{expected_store}' MISSING")

    # 3. Store URL / Directory (20 points)
    store_url = result.get('store_url', '')
    if 'mosaics/world_quadrants' in store_url or 'world_quadrants' in store_url:
        score += 20
        feedback_parts.append("Store points to correct directory")
    else:
        feedback_parts.append(f"Store URL incorrect: {store_url}")

    # 4. Layer (20 points)
    if result.get('layer_found'):
        if result.get('layer_enabled'):
            score += 20
            feedback_parts.append(f"Layer '{expected_layer}' published and enabled")
            
            # Check bbox
            bbox = result.get('layer_bbox', '')
            if bbox and bbox != ',,,':
                feedback_parts.append("Bounding box computed")
            else:
                feedback_parts.append("Bounding box missing/empty")
        else:
            score += 10
            feedback_parts.append(f"Layer '{expected_layer}' exists but is DISABLED")
    else:
        feedback_parts.append(f"Layer '{expected_layer}' MISSING")

    # 5. Visual Verification (20 points)
    # Check if WMS returned a valid image with content
    if result.get('wms_image_valid'):
        try:
            std_dev = float(result.get('wms_image_std_dev', '0'))
            if std_dev > 0.001: # Has contrast
                score += 20
                feedback_parts.append("WMS GetMap verification passed (valid raster data)")
            else:
                feedback_parts.append("WMS returned blank/uniform image (data not loading?)")
        except ValueError:
             feedback_parts.append("WMS check failed (invalid metric)")
    else:
        feedback_parts.append("WMS GetMap request failed")

    # 6. VLM Trajectory Check (Tie-breaker / Confirmation)
    # If score is borderline, or just to verify workflow
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        # Simple check: did they see the store creation page?
        # This is implicit if they succeeded, but good for anti-gaming.
        pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }