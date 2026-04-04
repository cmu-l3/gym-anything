#!/usr/bin/env python3
"""Verifier for configure_kml_regionation task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_kml_regionation(traj, env_info, task_info):
    """
    Verify that KML regionation was configured correctly for ne_populated_places.
    
    Criteria:
    1. Regionation Strategy must be 'external-sorting' (40 pts)
    2. Regionation Attribute must be 'pop_max' (40 pts)
    3. Layer must remain enabled (10 pts)
    4. GUI interaction / VLM verification (10 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_strategy = metadata.get('expected_strategy', 'external-sorting')
    expected_attribute = metadata.get('expected_attribute', 'pop_max')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_kml_regionation_result.json", temp_file.name)
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
        # If nonce file is missing but result has one, that's suspicious
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce validation error"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    # Parse results
    config = result.get('layer_config', {})
    actual_strategy = config.get('strategy', '')
    actual_attribute = config.get('attribute', '')
    layer_enabled = config.get('enabled', False)
    gui_interaction = result.get('gui_interaction_detected', False)

    score = 0
    feedback_parts = []
    
    # 1. Verify Strategy (40 points)
    if actual_strategy == expected_strategy:
        score += 40
        feedback_parts.append(f"Strategy correct: '{actual_strategy}'")
    else:
        feedback_parts.append(f"Strategy incorrect: '{actual_strategy}' (expected '{expected_strategy}')")

    # 2. Verify Attribute (40 points)
    if actual_attribute == expected_attribute:
        score += 40
        feedback_parts.append(f"Attribute correct: '{actual_attribute}'")
    else:
        feedback_parts.append(f"Attribute incorrect: '{actual_attribute}' (expected '{expected_attribute}')")

    # 3. Verify Layer Integrity (10 points)
    if layer_enabled:
        score += 10
        feedback_parts.append("Layer is enabled")
    else:
        feedback_parts.append("Layer was disabled (fail)")

    # 4. VLM / GUI Verification (10 points)
    # We combine the access log check (gui_interaction) with a VLM check
    vlm_confirmed = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        # Use VLM to check if the agent actually visited the Publishing tab
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=5)
        
        if frames:
            vlm_result = query_vlm(
                images=frames,
                prompt=(
                    "Do these screenshots show a user configuring a layer in GeoServer? "
                    "Look for tabs named 'Data', 'Publishing', 'Dimensions', 'Tile Caching'. "
                    "Specifically, is the 'Publishing' tab or 'KML Format Settings' visible in any frame? "
                    "Respond with JSON: {\"publishing_tab_visible\": true/false, \"confidence\": \"high/medium/low\"}"
                )
            )
            
            if isinstance(vlm_result, dict) and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('publishing_tab_visible', False):
                    vlm_confirmed = True
                    feedback_parts.append("VLM confirmed Publishing tab visit")

    # Award points if EITHER logs or VLM confirmed interaction
    if gui_interaction or vlm_confirmed:
        score += 10
        feedback_parts.append("GUI interaction confirmed")
    elif score == 90: 
        # If they got everything else right but we missed the GUI signal, 
        # we might still give them full points if it's purely a programmatic verification limitation,
        # but to encourage anti-gaming we penalize slightly or rely on the robust check.
        # Here we'll just note it.
        feedback_parts.append("No GUI interaction detected (API usage suspected?)")

    passed = (score >= 90) # Requires Strategy(40) + Attribute(40) + Enabled(10)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }