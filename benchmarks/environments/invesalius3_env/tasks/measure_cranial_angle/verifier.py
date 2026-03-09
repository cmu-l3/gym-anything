#!/usr/bin/env python3
"""
Verifier for measure_cranial_angle task.

Scoring (100 points total):
  - Project file saved at correct path:           15 pts
  - File created/modified during task:            10 pts
  - Valid .inv3 archive format:                   10 pts
  - Measurements data found in project:           20 pts
  - At least one ANGULAR measurement found:       20 pts
  - Angle value is physiologically valid (30-170): 25 pts

Pass threshold: 75 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measure_cranial_angle(traj, env_info, task_info):
    """Verify that the agent placed a valid angular measurement."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_angle = metadata.get("min_angle_degrees", 30.0)
    max_angle = metadata.get("max_angle_degrees", 170.0)

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/measure_cranial_angle_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: File exists (15 pts) ---
    if result.get("file_exists"):
        score += 15
        feedback_parts.append("Project file exists")
    else:
        feedback_parts.append("Project file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Valid archive (10 pts) ---
    if result.get("valid_archive"):
        score += 10
        feedback_parts.append("Valid .inv3 format")
    else:
        feedback_parts.append("Invalid or corrupt project file")

    # --- Criterion 3: Created during task (10 pts) ---
    if result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("File created during session")
    else:
        feedback_parts.append("File timestamp pre-dates task (anti-gaming)")

    # --- Criterion 4: Measurements data found (20 pts) ---
    if result.get("measurements_found") or result.get("angular_measurements_count", 0) > 0:
        score += 20
        feedback_parts.append("Measurement data detected")
    else:
        feedback_parts.append("No measurement data found in project")

    # --- Criterion 5: Angular measurement found (20 pts) ---
    angle_count = result.get("angular_measurements_count", 0)
    if angle_count > 0:
        score += 20
        feedback_parts.append(f"Found {angle_count} angular measurement(s)")
    else:
        feedback_parts.append("No specific angular measurements identified (did you use linear tool?)")

    # --- Criterion 6: Valid angle value (25 pts) ---
    valid_count = result.get("valid_angle_values_count", 0)
    vals = result.get("angle_values", [])
    if valid_count > 0:
        score += 25
        val_strs = [f"{v:.1f}" for v in vals]
        feedback_parts.append(f"Valid anatomical angle(s): {', '.join(val_strs)} deg")
    else:
        if vals:
            val_strs = [f"{v:.1f}" for v in vals]
            feedback_parts.append(f"Angles out of range ({min_angle}-{max_angle}): {', '.join(val_strs)}")
        else:
            feedback_parts.append("No angle values to validate")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "angle_values": result.get("angle_values", []),
            "counts": angle_count
        }
    }