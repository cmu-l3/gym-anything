#!/usr/bin/env python3
"""
Verifier for publish_reprojected_layer task.
Scores the creation of a reprojected PostGIS layer in GeoServer.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_publish_reprojected_layer(traj, env_info, task_info):
    """
    Verify that ne_countries_3857 was created with correct SRS and projection policy.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_layer = metadata.get('expected_layer_name', 'ne_countries_3857')
    expected_native = metadata.get('expected_native_name', 'ne_countries')
    expected_srs = metadata.get('expected_srs', 'EPSG:3857')
    expected_title_fragment = "Web Mercator"
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
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
        # If nonce check fails but result exists, we penalize or fail
        if result.get('result_nonce'):
             return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce verification error"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Layer Exists (15 pts)
    if result.get('layer_exists'):
        score += 15
        feedback_parts.append(f"Layer '{expected_layer}' exists")
    else:
        return {"passed": False, "score": 0, "feedback": f"Layer '{expected_layer}' not found"}

    # 2. Correct Native Name (15 pts)
    native_name = result.get('native_name', '')
    if native_name == expected_native:
        score += 15
        feedback_parts.append(f"Native table correctly set to '{native_name}'")
    else:
        feedback_parts.append(f"Incorrect native table: '{native_name}' (expected '{expected_native}')")

    # 3. Declared SRS is EPSG:3857 (20 pts)
    declared_srs = result.get('declared_srs', '')
    if declared_srs == expected_srs:
        score += 20
        feedback_parts.append(f"Declared SRS correct: '{declared_srs}'")
    else:
        feedback_parts.append(f"Incorrect SRS: '{declared_srs}' (expected '{expected_srs}')")

    # 4. Projection Policy (15 pts)
    policy = result.get('projection_policy', '')
    if policy in ['REPROJECT', 'FORCE', 'REPROJECT_TO_DECLARED']:
        score += 15
        feedback_parts.append(f"Projection policy correct: '{policy}'")
    else:
        feedback_parts.append(f"Incorrect projection policy: '{policy}' (expected REPROJECT/FORCE)")

    # 5. Title (10 pts)
    title = result.get('layer_title', '')
    if expected_title_fragment.lower() in title.lower():
        score += 10
        feedback_parts.append("Layer title contains 'Web Mercator'")
    elif title:
        score += 5
        feedback_parts.append(f"Layer title set to '{title}' (partial credit)")
    else:
        feedback_parts.append("Layer title missing or empty")

    # 6. WMS GetMap Success (15 pts)
    if result.get('wms_success'):
        score += 15
        feedback_parts.append("WMS GetMap request successful")
    else:
        feedback_parts.append("WMS GetMap request failed")

    # 7. Image Content (10 pts)
    if result.get('wms_content_valid'):
        score += 10
        feedback_parts.append("WMS image contains valid map content")
    else:
        feedback_parts.append("WMS image appears blank or empty")

    # Anti-gaming check: Ensure layer count increased
    initial_count = int(result.get('initial_layer_count', 0))
    current_count = int(result.get('current_layer_count', 0))
    if current_count <= initial_count:
        feedback_parts.append("WARNING: Layer count did not increase")
        # We don't fail, but we note it. If they deleted and recreated, count might be same, 
        # but the logic in setup deletes the target layer first, so count should increase by 1.
        # Unless they deleted other layers.

    # VLM Trajectory Verification (Optional bonus/sanity check)
    # Checks if user actually interacted with the interface if REST API wasn't the only method
    # For now, relying on programmatic checks as primary.

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }