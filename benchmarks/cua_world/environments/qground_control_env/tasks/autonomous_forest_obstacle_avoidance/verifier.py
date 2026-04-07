#!/usr/bin/env python3
"""
Verifier for autonomous_forest_obstacle_avoidance task.

Validates that 8 specific parameters regarding LiDAR and obstacle avoidance
were successfully set via QGroundControl.

Expected Values:
- PRX1_TYPE: 5
- SERIAL2_PROTOCOL: 11
- SERIAL2_BAUD: 115
- OA_TYPE: 1
- OA_BR_LOOKAHEAD: 8
- OA_MARGIN_MAX: 2.5
- AVOID_ENABLE: 2
- WPNAV_SPEED: 300
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Dictionary containing parameter name, expected value, tolerance, and points
REQUIRED_PARAMS = {
    'PRX1_TYPE':        (5.0,   0.4, 13),
    'SERIAL2_PROTOCOL': (11.0,  0.4, 13),
    'SERIAL2_BAUD':     (115.0, 0.4, 13),
    'OA_TYPE':          (1.0,   0.4, 13),
    'OA_BR_LOOKAHEAD':  (8.0,   0.5, 12),
    'OA_MARGIN_MAX':    (2.5,   0.2, 12),
    'AVOID_ENABLE':     (2.0,   0.4, 12),
    'WPNAV_SPEED':      (300.0, 15.0, 12)
}

def verify_autonomous_forest_obstacle_avoidance(traj, env_info, task_info):
    """
    Verification logic using `copy_from_env` to read post-task parameters.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    params = result.get('params', {})
    
    # Check if SITL was reachable during export_result phase
    if not params.get('connected', True) and all(params.get(p) is None for p in REQUIRED_PARAMS):
        return {
            'passed': False, 
            'score': 0,
            'feedback': 'SITL not reachable during export. No parameters could be verified.'
        }

    score = 0
    feedback_parts = []
    details = {}

    for param_name, (expected_val, tolerance, pts) in REQUIRED_PARAMS.items():
        actual = params.get(param_name)
        details[param_name] = actual

        if actual is None:
            feedback_parts.append(f"{param_name}: Not read (+0/{pts})")
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback_parts.append(f"{param_name}: Invalid value '{actual}' (+0/{pts})")
            continue

        if abs(actual_f - expected_val) <= tolerance:
            score += pts
            feedback_parts.append(f"{param_name}={actual_f:.1f} ✓ (+{pts})")
        else:
            feedback_parts.append(f"{param_name}={actual_f:.1f} (Expected ~{expected_val:.1f}) (+0/{pts})")

    # Pass condition: must score at least 75 points (requires >6/8 parameters to be correct)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }