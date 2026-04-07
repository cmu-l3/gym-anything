#!/usr/bin/env python3
"""
Verifier for compass_orientation_config task.

Reads /tmp/task_result.json (populated by export_result.sh via pymavlink) and scores
each of the 8 compass/orientation parameters against required values specified in task metadata.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compass_orientation(traj, env_info, task_info):
    """Verify compass orientation configuration task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    expected_params = metadata.get('expected_params', {})
    pass_threshold = metadata.get('pass_threshold', 65)

    if not expected_params:
        return {"passed": False, "score": 0, "feedback": "Verifier configuration error: Missing expected parameters"}

    # Load result
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

    scoring = {
        "total_points": 0,
        "details": [],
        "pass": False,
    }

    params = result.get("parameters", {})
    feedback_parts = []

    # Check each parameter
    for param_name, config in expected_params.items():
        expected = config.get("value")
        tolerance = config.get("tolerance")
        points = config.get("points")
        
        actual = params.get(param_name)

        if actual is None:
            feedback_parts.append(f"{param_name}: missing (+0/{points})")
            scoring["details"].append(f"FAIL ({param_name}): Parameter not read (0/{points} pts)")
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback_parts.append(f"{param_name}: invalid '{actual}' (+0/{points})")
            scoring["details"].append(f"FAIL ({param_name}): Invalid value '{actual}' (0/{points} pts)")
            continue

        diff = abs(actual_f - expected)
        if diff <= tolerance:
            scoring["total_points"] += points
            feedback_parts.append(f"{param_name}={actual_f} ✓ (+{points})")
            scoring["details"].append(f"PASS ({param_name}): {actual_f} == {expected} (within ±{tolerance}) -> +{points} pts")
        else:
            feedback_parts.append(f"{param_name}={actual_f} (need {expected}) (+0/{points})")
            scoring["details"].append(f"FAIL ({param_name}): {actual_f} != {expected} (diff={diff:.2f}, tol=±{tolerance}) -> 0/{points} pts")

    # Anti-gaming checks: Processes must be alive
    if not result.get("sitl_running", False):
        feedback_parts.append("WARNING: SITL crashed")
        scoring["details"].append("WARNING: ArduPilot SITL not running at export time")
    if not result.get("qgc_running", False):
        feedback_parts.append("WARNING: QGC closed")
        scoring["details"].append("WARNING: QGroundControl not running at export time")

    # Finalize scoring
    scoring["pass"] = scoring["total_points"] >= pass_threshold
    
    return {
        "passed": scoring["pass"],
        "score": scoring["total_points"],
        "feedback": " | ".join(feedback_parts),
        "details": scoring["details"]
    }