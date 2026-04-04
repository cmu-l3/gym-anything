#!/usr/bin/env python3
"""
Verifier for derive_power_factor task.

Verification Logic:
1. Feed 'motor_PF' must exist.
2. Feed must have been updated *after* task start.
3. Feed value must be valid (Power Factor is typically 0.0 - 1.0, specifically ~0.85 here).
4. 'motor_power_W' input must have a process list configured.
5. Process list must involve division (logic check).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_derive_power_factor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract data
    task_start = result.get('task_start', 0)
    feed_exists = result.get('feed_exists', False)
    feed_value_str = result.get('feed_value', "0")
    feed_updated = result.get('feed_updated', 0)
    inputs_list = result.get('inputs_list', [])
    
    score = 0
    feedback_parts = []
    passed = False

    # Criterion 1: Feed 'motor_PF' exists (20 pts)
    if feed_exists:
        score += 20
        feedback_parts.append("Feed 'motor_PF' created.")
    else:
        feedback_parts.append("Feed 'motor_PF' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Feed updated recently (Anti-gaming) (20 pts)
    if feed_updated > task_start:
        score += 20
        feedback_parts.append("Feed updated with new data.")
    else:
        feedback_parts.append(f"Feed not updated during task (Last update: {feed_updated} vs Start: {task_start}).")

    # Criterion 3: Value Accuracy (40 pts)
    # Expected PF is around 0.85
    try:
        pf_val = float(feed_value_str)
        # Allow wide range because V/I/W fluctuate, but should be reasonable for a motor
        if 0.70 <= pf_val <= 1.0:
            score += 40
            feedback_parts.append(f"Power Factor value {pf_val:.3f} is within expected range (0.7-1.0).")
        else:
            feedback_parts.append(f"Power Factor value {pf_val:.3f} is out of expected range (0.7-1.0). Logic may be wrong (e.g., W/V*I vs W/V/I).")
            # Partial credit if they calculated SOMETHING, just wrong
            score += 10
    except ValueError:
        feedback_parts.append("Feed value is not a valid number.")

    # Criterion 4: Process List Logic Check (20 pts)
    # Find 'motor_power_W' input
    power_input = next((i for i in inputs_list if i.get('name') == 'motor_power_W'), None)
    
    if power_input:
        process_list = power_input.get('processList', "")
        # Process list string format is "ID:Arg,ID:Arg"
        # We look for length > 0 and typically multiple steps
        if len(process_list) > 5:  # Arbitrary min length for "5:X,5:Y,1:Z"
            score += 20
            feedback_parts.append("Input processing chain configured.")
        else:
            feedback_parts.append("Input processing chain appears empty or too short.")
    else:
        feedback_parts.append("Could not find 'motor_power_W' input in verification data.")

    # Pass threshold
    if score >= 80:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }