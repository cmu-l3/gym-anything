#!/usr/bin/env python3
"""Verifier for publish_shapefile_directory_store task."""

import json
import tempfile
import os

def verify_publish_shapefile_directory_store(traj, env_info, task_info):
    """Verify Shapefile directory store creation and layer publication."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/publish_shp_dir_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce check failed"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # 1. Data staged in container (10 pts)
    if result.get('files_in_container'):
        score += 10
        feedback_parts.append("Shapefiles staged in container")
    else:
        feedback_parts.append("Shapefiles NOT found in container")

    # 2. Workspace created (10 pts)
    if result.get('workspace_found'):
        score += 10
        feedback_parts.append("Workspace 'shp_ne' created")
        # Check URI (5 pts)
        if 'shp_ne.example.org' in result.get('workspace_uri', ''):
            score += 5
            feedback_parts.append("Workspace URI correct")
    else:
        feedback_parts.append("Workspace 'shp_ne' NOT found")

    # 3. Datastore created (15 pts)
    store_found = result.get('store_found')
    if store_found:
        score += 15
        feedback_parts.append("Datastore 'shp_directory' created")
        
        # Check Type (Directory of shapefiles) - 10 pts
        store_type = result.get('store_type', '').lower()
        if 'shapefile' in store_type or 'directory' in store_type:
            score += 10
            feedback_parts.append("Datastore type correct (Shapefile/Directory)")
        else:
            feedback_parts.append(f"Datastore type incorrect: {store_type}")
            
        # Check connection path matches container path (5 pts)
        conn = result.get('store_connection', '')
        if 'shp_data' in conn:
            score += 5
            feedback_parts.append("Datastore path correct")
    else:
        feedback_parts.append("Datastore 'shp_directory' NOT found")

    # 4. Layers Published (20 pts)
    if result.get('countries_layer_found'):
        score += 10
        feedback_parts.append("Countries layer published")
    else:
        feedback_parts.append("Countries layer MISSING")

    if result.get('lakes_layer_found'):
        score += 10
        feedback_parts.append("Lakes layer published")
    else:
        feedback_parts.append("Lakes layer MISSING")

    # 5. Output Images (25 pts)
    # Countries image
    c_exists = result.get('countries_image_exists')
    c_size = result.get('countries_image_size', 0)
    if c_exists and c_size > 5000:
        score += 12.5
        feedback_parts.append("Countries map image saved")
    elif c_exists:
        score += 5
        feedback_parts.append("Countries map image too small/empty")
    
    # Lakes image
    l_exists = result.get('lakes_image_exists')
    l_size = result.get('lakes_image_size', 0)
    if l_exists and l_size > 5000:
        score += 12.5
        feedback_parts.append("Lakes map image saved")
    elif l_exists:
        score += 5
        feedback_parts.append("Lakes map image too small/empty")

    # VLM Trajectory Verification (Optional, if available)
    # Ensure GUI was used if possible
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj and result.get('gui_interaction_detected'):
        # Just confirmation
        pass
    elif query_vlm and traj and not result.get('gui_interaction_detected'):
        # Penalize for pure API use if detected? 
        # For now, just note it.
        feedback_parts.append("(Note: Minimal GUI interaction detected)")

    passed = score >= 70 and result.get('files_in_container') and store_found and result.get('countries_layer_found')

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }