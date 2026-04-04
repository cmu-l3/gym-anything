#!/usr/bin/env python3
"""
Verifier for configure_payment_gateway task.

Scoring (100 points total):
- Gateway exists with "Bank Transfer" in label (20 pts)
- Plugin is 'manual' (15 pts)
- Display label is 'Bank Wire Transfer' (15 pts)
- Mode is 'live' (15 pts)
- Instructions contain required account details (20 pts)
- Status is enabled (15 pts)

Pass threshold: 70 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_payment_gateway(traj, env_info, task_info):
    """
    Verify the created payment gateway configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strings = metadata.get('required_instruction_strings', [])

    try:
        # Load result JSON from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/payment_gateway_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                gateways = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}

    if not gateways or not isinstance(gateways, list):
        return {"passed": False, "score": 0, "feedback": "No payment gateways found in system."}

    # Find the best candidate gateway
    # We look for a 'manual' gateway or one with 'Bank' in the label created during the task
    best_candidate = None
    best_score = -1
    
    # Heuristic to find the target gateway if multiple exist
    for gw in gateways:
        label = gw.get('label', '')
        if 'Bank' in label or 'Transfer' in label:
            best_candidate = gw
            break
    
    # If no obvious match, take the most recent new one
    if not best_candidate:
        for gw in gateways:
            if gw.get('is_new') == "true":
                best_candidate = gw
                break

    if not best_candidate:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No relevant payment gateway found (looking for 'Bank Transfer' or new manual gateway)."
        }

    # Now evaluate the best candidate
    gw = best_candidate
    score = 0
    feedback_parts = []
    
    # 1. Label Check (20 pts)
    label = gw.get('label', '')
    if "Bank Transfer" in label:
        score += 20
        feedback_parts.append(f"Correct label '{label}'")
    elif "Bank" in label:
        score += 10
        feedback_parts.append(f"Label '{label}' contains 'Bank' but not exact match")
    else:
        feedback_parts.append(f"Label mismatch: '{label}'")

    # 2. Plugin Check (15 pts)
    plugin = gw.get('plugin', '')
    if plugin == 'manual':
        score += 15
        feedback_parts.append("Correct plugin (Manual)")
    else:
        feedback_parts.append(f"Wrong plugin type: '{plugin}'")

    # 3. Display Label Check (15 pts)
    # Configuration is usually nested under 'configuration' key
    config = gw.get('configuration', {})
    display_label = config.get('display_label', '')
    
    if display_label == "Bank Wire Transfer":
        score += 15
        feedback_parts.append("Correct display label")
    elif "Wire" in display_label:
        score += 10
        feedback_parts.append(f"Display label partial match: '{display_label}'")
    else:
        feedback_parts.append(f"Display label mismatch: '{display_label}'")

    # 4. Mode Check (15 pts)
    mode = config.get('mode', '')
    if mode == 'live':
        score += 15
        feedback_parts.append("Mode is Live")
    elif mode == 'test':
        feedback_parts.append("Mode is Test (expected Live)")
    else:
        feedback_parts.append(f"Unknown mode: '{mode}'")

    # 5. Status Check (15 pts)
    status = gw.get('status', False)
    if status is True or str(status).lower() == 'true' or status == 1:
        score += 15
        feedback_parts.append("Gateway enabled")
    else:
        feedback_parts.append("Gateway disabled")

    # 6. Instructions Check (20 pts)
    instructions_raw = config.get('instructions', {})
    # instructions might be a dict with 'value' and 'format', or just a string
    instructions_text = ""
    if isinstance(instructions_raw, dict):
        instructions_text = instructions_raw.get('value', '')
    elif isinstance(instructions_raw, str):
        instructions_text = instructions_raw
    
    found_strings = 0
    missing_strings = []
    
    for req in required_strings:
        if req in instructions_text:
            found_strings += 1
        else:
            missing_strings.append(req)
    
    if found_strings == len(required_strings):
        score += 20
        feedback_parts.append("Instructions correct")
    elif found_strings > 0:
        partial = int(20 * (found_strings / len(required_strings)))
        score += partial
        feedback_parts.append(f"Instructions partial ({found_strings}/{len(required_strings)} matches)")
    else:
        feedback_parts.append("Instructions missing required details")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }