#!/usr/bin/env python3
"""
Verifier for measure_skull_and_save task.

Scoring (100 points total):
  - Project file saved at correct path:                   20 pts
  - Valid InVesalius .inv3 format:                        15 pts
  - At least 1 measurement present:                       25 pts
  - At least 2 measurements present (both diameters):     20 pts
  - Both measurements > 80 mm (plausible cranial dims):   20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_measure_skull_and_save(traj, env_info, task_info):
    """Verify that the agent placed skull measurements and saved the project."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_val = metadata.get("min_measurement_value_mm", 80.0)
    required_count = metadata.get("required_measurement_count", 2)

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/measure_skull_and_save_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: Project file exists ---
    if result.get("file_exists"):
        score += 20
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append(
            "Project file not found at /home/ga/Documents/cranial_measurements.inv3"
        )
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Valid .inv3 format ---
    if result.get("valid_inv3"):
        score += 15
        feedback_parts.append("Valid InVesalius project format")
    else:
        feedback_parts.append(
            f"Invalid .inv3 format: {result.get('parse_error', 'unknown')}"
        )

    # --- Criterion 3: At least 1 measurement ---
    mcount = result.get("measurement_count", 0)
    if mcount >= 1:
        score += 25
        feedback_parts.append(f"{mcount} measurement(s) found")
    else:
        feedback_parts.append("No measurements found in project")

    # --- Criterion 4: At least 2 measurements ---
    if mcount >= required_count:
        score += 20
        feedback_parts.append(f"Both required measurements present ({mcount} total)")
    else:
        feedback_parts.append(
            f"Only {mcount} measurement(s); need {required_count} (transverse + anteroposterior)"
        )

    # --- Criterion 5: Both measurements > 80 mm ---
    above_threshold = result.get("measurements_above_80mm", 0)
    measurements = result.get("measurements", [])
    if above_threshold >= required_count:
        score += 20
        vals = [f"{m['value_mm']:.1f} mm" for m in measurements]
        feedback_parts.append(f"Measurements in valid range: {', '.join(vals)}")
    else:
        vals = [f"{m['value_mm']:.1f} mm" for m in measurements]
        feedback_parts.append(
            f"Measurements too small or count insufficient (need {required_count} > {min_val} mm; got: {', '.join(vals) or 'none'})"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {"measurements": result.get("measurements", [])},
    }
