#!/usr/bin/env python3
"""
Verifier for LiDAR Payload Navigation Tuning task.

Checks 7 WPNAV/LOIT/RTL safety parameters via pymavlink values recorded in export_result.sh.

Required values (all different from factory defaults):
  WPNAV_SPEED     = 800  (default: 500)
  WPNAV_SPEED_UP  = 150  (default: 250)
  WPNAV_SPEED_DN  = 100  (default: 150)
  WPNAV_ACCEL     = 200  (default: 100)
  WPNAV_RADIUS    = 300  (default: 200)
  LOIT_SPEED      = 800  (default: 1250)
  RTL_SPEED       = 500  (default: 0)

Scoring (100 pts total, pass = 60):
  15 pts for WPNAV_SPEED, WPNAV_SPEED_UP, WPNAV_SPEED_DN
  14 pts for WPNAV_ACCEL, WPNAV_RADIUS, LOIT_SPEED
  13 pts for RTL_SPEED
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lidar_payload_nav_tuning(traj, env_info, task_info):
    """
    Verify that all 7 navigation parameters are set correctly to the spec values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')
    required_params = metadata.get('required_params', {})

    # Default mappings as fallback if metadata is missing
    if not required_params:
        required_params = {
            "WPNAV_SPEED":    {"target": 800.0,  "tol": 15.0, "default": 500.0, "points": 15},
            "WPNAV_SPEED_UP": {"target": 150.0,  "tol": 15.0, "default": 250.0, "points": 15},
            "WPNAV_SPEED_DN": {"target": 100.0,  "tol": 15.0, "default": 150.0, "points": 15},
            "WPNAV_ACCEL":    {"target": 200.0,  "tol": 15.0, "default": 100.0, "points": 14},
            "WPNAV_RADIUS":   {"target": 300.0,  "tol": 25.0, "default": 200.0, "points": 14},
            "LOIT_SPEED":     {"target": 800.0,  "tol": 15.0, "default": 1250.0, "points": 14},
            "RTL_SPEED":      {"target": 500.0,  "tol": 15.0, "default": 0.0,   "points": 13},
        }

    # Extract JSON results
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp_file.name)
        with open(tmp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    if not result.get("query_success"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Parameter query failed: {result.get('error', 'Unknown Error')}"
        }

    params = result.get("parameters", {})
    if not params:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No parameters returned from SITL."
        }

    total_score = 0
    correct_count = 0
    feedback_parts = []
    details = {}

    for param_name, req in required_params.items():
        actual = params.get(param_name)
        target = req["target"]
        tol = req["tol"]
        pts = req["points"]
        default = req["default"]
        
        details[param_name] = actual

        if actual is None:
            feedback_parts.append(f"{param_name}: not queried (+0)")
            continue

        try:
            actual_f = float(actual)
        except (TypeError, ValueError):
            feedback_parts.append(f"{param_name}: invalid format {actual} (+0)")
            continue

        diff = abs(actual_f - target)

        if diff <= tol:
            feedback_parts.append(f"{param_name}={actual_f:.0f} ✓ (+{pts})")
            total_score += pts
            correct_count += 1
        else:
            # Check for do-nothing gaming (still at default)
            if abs(actual_f - default) < 1.0:
                feedback_parts.append(f"{param_name}={actual_f:.0f} (still at factory default {default}) (+0)")
            else:
                feedback_parts.append(f"{param_name}={actual_f:.0f} (need {target} ±{tol}) (+0)")

    # Construct final feedback string
    qgc_running = result.get("qgc_running", False)
    if not qgc_running:
        feedback_parts.append("Note: QGroundControl was not running during export.")

    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }