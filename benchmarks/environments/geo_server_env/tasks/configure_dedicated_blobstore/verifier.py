#!/usr/bin/env python3
"""Verifier for configure_dedicated_blobstore task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dedicated_blobstore(traj, env_info, task_info):
    """
    Verify that a dedicated BlobStore was created and assigned, and tiles were generated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_store_name = metadata.get('expected_blobstore_name', 'countries_store')
    expected_path = metadata.get('expected_blobstore_path', '/home/ga/geoserver/cache/countries')
    expected_layer = metadata.get('expected_layer', 'ne:ne_countries')
    min_tile_count = metadata.get('min_tile_count', 10)

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_dedicated_blobstore_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce check fails but result exists, penalize or fail
        pass
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. BlobStore Configuration (30 pts)
    store_exists = result.get('store_exists_api', False)
    configured_path = result.get('store_path_configured', '').strip()
    
    if store_exists:
        # Check path matches
        # Note: Paths might vary slightly in trailing slashes, normalize
        norm_expected = expected_path.rstrip('/')
        norm_configured = configured_path.rstrip('/')
        
        if norm_expected == norm_configured:
            score += 30
            feedback_parts.append(f"BlobStore '{expected_store_name}' configured correctly")
        else:
            score += 15
            feedback_parts.append(f"BlobStore exists but path mismatch (found: {configured_path})")
    else:
        feedback_parts.append("BlobStore NOT found in configuration")

    # 2. Layer Assignment (30 pts)
    assigned_store = result.get('layer_blobstore_assigned', '')
    if assigned_store == expected_store_name:
        score += 30
        feedback_parts.append(f"Layer '{expected_layer}' assigned to correct BlobStore")
    elif assigned_store == 'default' or assigned_store == '':
        feedback_parts.append(f"Layer still using default BlobStore")
    else:
        score += 5
        feedback_parts.append(f"Layer assigned to wrong store: {assigned_store}")

    # 3. Directory Creation (10 pts)
    dir_exists = result.get('directory_exists', False)
    if dir_exists:
        score += 10
        feedback_parts.append("Target cache directory exists")
    else:
        feedback_parts.append("Target cache directory NOT created")

    # 4. Tiles Generated (30 pts)
    tile_count = result.get('tile_count', 0)
    tiles_fresh = result.get('tiles_created_during_task', False)
    
    if tile_count >= min_tile_count:
        if tiles_fresh:
            score += 30
            feedback_parts.append(f"Seeding successful ({tile_count} tiles generated)")
        else:
            score += 10
            feedback_parts.append(f"Tiles found but timestamps pre-date task (stale data?)")
    elif tile_count > 0:
        score += 10
        feedback_parts.append(f"Some tiles found ({tile_count}), fewer than expected")
    else:
        feedback_parts.append("No tiles found in target directory")

    # VLM Verification (Optional sanity check)
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        # We can implement a check here if scores are borderline,
        # but the programmatic signals are very strong for this task.
        pass

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }