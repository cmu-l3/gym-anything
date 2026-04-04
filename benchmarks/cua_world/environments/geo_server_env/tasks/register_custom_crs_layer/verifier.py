#!/usr/bin/env python3
"""Verifier for register_custom_crs_layer task."""

import json
import tempfile
import os

def verify_register_custom_crs_layer(traj, env_info, task_info):
    """Verify that a custom CRS was registered and a layer published with it."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_srs = "EPSG:990001"
    
    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/register_custom_crs_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Custom CRS Registration (30 pts)
    if result.get('crs_registered'):
        score += 30
        feedback_parts.append("Custom CRS '990001' found in epsg.properties")
    else:
        feedback_parts.append("Custom CRS '990001' NOT found in registry")

    # 2. WKT Correctness (10 pts)
    if result.get('wkt_correct'):
        score += 10
        feedback_parts.append("WKT definition appears correct (central_meridian=150.0)")
    elif result.get('crs_registered'):
        feedback_parts.append("WKT definition incorrect or missing parameters")

    # 3. Layer Published (20 pts)
    if result.get('layer_found'):
        score += 20
        feedback_parts.append(f"Layer '{result.get('layer_name')}' found")
    else:
        feedback_parts.append("Target layer NOT found")

    # 4. Layer Configuration (20 pts)
    layer_srs = result.get('layer_srs', '')
    policy = result.get('projection_policy', '')
    
    srs_ok = layer_srs == expected_srs
    policy_ok = policy in ['REPROJECT_TO_DECLARED', 'FORCE_DECLARED']
    
    if srs_ok:
        score += 10
        feedback_parts.append(f"Layer declared SRS is correct ({expected_srs})")
    else:
        feedback_parts.append(f"Layer SRS incorrect: {layer_srs}")
        
    if policy_ok:
        score += 10
        feedback_parts.append(f"Projection policy correct ({policy})")
    else:
        feedback_parts.append(f"Projection policy incorrect: {policy} (expected REPROJECT_TO_DECLARED)")

    # 5. Functional WMS Test (20 pts)
    if result.get('wms_success'):
        score += 20
        feedback_parts.append("WMS GetMap request with custom SRS succeeded")
    else:
        feedback_parts.append("WMS GetMap request failed (check reprojection setup)")

    # VLM Verification (for GUI usage confirmation)
    # This prevents users from just using REST API if the task implies GUI, 
    # though technically REST API is a valid power-user method. 
    # However, for this task, we want to ensure they can use the Custom CRS UI.
    query_vlm = env_info.get('query_vlm')
    gui_interaction = result.get('gui_interaction_detected', False)
    
    if query_vlm and traj:
        # Check if we have visual evidence of the SRS editor
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        
        vlm_result = query_vlm(
            images=frames,
            prompt="Does any of these screenshots show the GeoServer 'SRS List' or 'New SRS' page? Look for a form with 'Code', 'Title', and 'WKT' fields."
        )
        
        if vlm_result.get('success'):
            if vlm_result.get('parsed', {}).get('answer', False) is True:
                 feedback_parts.append("Visual confirmation of SRS editor usage")
    
    passed = score >= 60 and result.get('crs_registered') and result.get('layer_found')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }