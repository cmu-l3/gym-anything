#!/usr/bin/env python3
"""
Verifier for Enable Time Dimension task.
Checks if the WMS time dimension is correctly configured on the earthquakes layer.
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_time_dimension(traj, env_info, task_info):
    """
    Verify that the time dimension is enabled and correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_attribute = metadata.get('expected_attribute', 'event_time')
    expected_presentation = metadata.get('expected_presentation', 'LIST')
    expected_strategy = metadata.get('expected_strategy', 'MAXIMUM')

    # Load result from container
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

    # Verify integrity nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Nonce file might be missing if task failed early, continue with checks
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Anti-gaming (5 points)
    # Ensure dimension was NOT enabled at start
    initial_state = result.get('initial_state', 'UNKNOWN')
    if initial_state == "NOT_ENABLED":
        score += 5
        feedback_parts.append("Initial state clean")
    else:
        feedback_parts.append(f"Initial state check failed: {initial_state}")

    # Check 2: Parse Feature Type JSON for Dimension Info
    # This is the detailed configuration check
    ft_data = result.get('feature_type', {})
    metadata_entries = ft_data.get('featureType', {}).get('metadata', {}).get('entry', [])
    if isinstance(metadata_entries, dict):
        metadata_entries = [metadata_entries]

    time_dim = None
    for entry in metadata_entries:
        if entry.get('@key') == 'time':
            time_dim = entry.get('dimensionInfo', {})
            break

    if not time_dim:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Time dimension NOT found in layer configuration. " + " | ".join(feedback_parts)
        }

    # Check 2a: Dimension Enabled (20 points)
    is_enabled = time_dim.get('enabled', False)
    if is_enabled is True or str(is_enabled).lower() == 'true':
        score += 20
        feedback_parts.append("Time dimension enabled")
    else:
        feedback_parts.append("Time dimension disabled")

    # Check 2b: Attribute Correct (20 points)
    attr = time_dim.get('attribute', '')
    if attr == expected_attribute:
        score += 20
        feedback_parts.append(f"Attribute correct ({attr})")
    else:
        feedback_parts.append(f"Attribute mismatch: found '{attr}', expected '{expected_attribute}'")

    # Check 2c: Presentation Mode (15 points)
    presentation = time_dim.get('presentation', '')
    if presentation == expected_presentation:
        score += 15
        feedback_parts.append(f"Presentation correct ({presentation})")
    else:
        feedback_parts.append(f"Presentation mismatch: found '{presentation}', expected '{expected_presentation}'")

    # Check 2d: Default Value Strategy (15 points)
    # structure is defaultValue: { strategy: "MAXIMUM" }
    default_val = time_dim.get('defaultValue', {})
    strategy = default_val.get('strategy', '') if isinstance(default_val, dict) else ''
    if strategy == expected_strategy:
        score += 15
        feedback_parts.append(f"Strategy correct ({strategy})")
    else:
        feedback_parts.append(f"Strategy mismatch: found '{strategy}', expected '{expected_strategy}'")

    # Check 3: WMS GetCapabilities (15 points)
    if result.get('get_capabilities_has_time'):
        score += 15
        feedback_parts.append("WMS Capabilities advertised time")
    else:
        feedback_parts.append("WMS Capabilities missing time dimension")

    # Check 4: WMS GetMap (10 points)
    get_map = result.get('get_map', {})
    if get_map.get('http_code') == '200' and get_map.get('size_bytes', 0) > 1000:
        score += 10
        feedback_parts.append("WMS GetMap returned valid image")
    else:
        feedback_parts.append(f"WMS GetMap failed (Code: {get_map.get('http_code')}, Size: {get_map.get('size_bytes')})")

    # Check 5: VLM / GUI Interaction (Rest API bypass check)
    # If the user just used curl to set the dimension, score might be high, 
    # but we want to encourage GUI usage if specified.
    # However, for pure correctness, we often accept programmatic solutions unless VLM proves "do nothing".
    # Here we just log it or could use it as a tiebreaker/penalty. 
    # Current logic: If score is high but no GUI interaction, prompt warning.
    if score >= 60 and not result.get('gui_interaction'):
        feedback_parts.append("Warning: No GUI interaction detected")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }