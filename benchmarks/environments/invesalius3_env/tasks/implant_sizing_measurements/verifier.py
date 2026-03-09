#!/usr/bin/env python3
"""
Verifier for implant_sizing_measurements task.

Scoring (100 points total):
  - Project file exists at correct path:           15 pts
  - Valid InVesalius .inv3 format:                 15 pts
  - At least 5 measurements present:               25 pts
  - All measurements >= 50 mm (realistic cranial): 20 pts
  - STL file exists at correct path:               15 pts
  - STL has >= 10,000 triangles (real geometry):   10 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_implant_sizing_measurements(traj, env_info, task_info):
    """Verify implant sizing: 5+ measurements + STL export + project save."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    required_measurements = metadata.get("required_measurement_count", 5)
    min_measurement_mm = metadata.get("min_measurement_value_mm", 50.0)
    min_triangles = metadata.get("min_stl_triangles", 10000)

    score = 0
    feedback_parts = []

    # Copy result JSON from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/implant_sizing_measurements_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: Project file exists (15 pts) ---
    if result.get("project_file_exists"):
        score += 15
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("FAIL: Project file not found at /home/ga/Documents/implant_plan.inv3")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Valid .inv3 format (15 pts) ---
    if result.get("project_valid_inv3"):
        score += 15
        feedback_parts.append("Valid InVesalius project format")
    else:
        err = result.get("project_parse_error", "unknown error")
        feedback_parts.append(f"FAIL: Invalid .inv3 format: {err}")

    # Independent verification: directly copy and re-parse the .inv3
    try:
        import tarfile
        import plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        try:
            copy_from_env("/home/ga/Documents/implant_plan.inv3", tmp_inv3.name)
            ind_measurement_count = 0
            ind_measurements = []
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                for member in t.getmembers():
                    name = os.path.basename(member.name)
                    if name == "measurements.plist":
                        f = t.extractfile(member)
                        meas_dict = plistlib.load(f)
                        ind_measurement_count = len(meas_dict)
                        for idx, meas in meas_dict.items():
                            ind_measurements.append(float(meas.get("value", 0)))

            # Use independent values if export JSON was incomplete
            if ind_measurement_count > result.get("measurement_count", 0):
                result["measurement_count"] = ind_measurement_count
                result["measurements"] = [{"value_mm": v} for v in ind_measurements]
                result["measurements_above_50mm"] = sum(
                    1 for v in ind_measurements if v >= min_measurement_mm
                )
        finally:
            try:
                os.unlink(tmp_inv3.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent .inv3 re-analysis failed: {e}")

    # --- Criterion 3: At least 5 measurements (25 pts) ---
    measurement_count = result.get("measurement_count", 0)
    if measurement_count >= required_measurements:
        score += 25
        feedback_parts.append(f"{measurement_count} measurements found (need >= {required_measurements})")
    elif measurement_count > 0:
        feedback_parts.append(
            f"FAIL: Only {measurement_count} measurement(s) found (need >= {required_measurements})"
        )
    else:
        feedback_parts.append("FAIL: No measurements found in project")

    # --- Criterion 4: All measurements >= 50 mm (20 pts) ---
    above_50 = result.get("measurements_above_50mm", 0)
    if measurement_count > 0 and above_50 >= required_measurements:
        score += 20
        feedback_parts.append(f"All {above_50} measurements >= {min_measurement_mm} mm (realistic cranial dimensions)")
    elif above_50 > 0:
        feedback_parts.append(
            f"FAIL: Only {above_50} of {measurement_count} measurements >= {min_measurement_mm} mm"
        )
    else:
        feedback_parts.append(f"FAIL: No measurements >= {min_measurement_mm} mm")

    # --- Criterion 5: STL file exists (15 pts) ---
    if result.get("stl_file_exists"):
        score += 15
        feedback_parts.append("STL file created at /home/ga/Documents/implant_sizing.stl")
    else:
        feedback_parts.append("FAIL: STL file not found at /home/ga/Documents/implant_sizing.stl")

    # --- Criterion 6: STL has >= 10,000 triangles (10 pts) ---
    triangle_count = result.get("stl_triangle_count", 0)
    if result.get("stl_valid") and triangle_count >= min_triangles:
        score += 10
        feedback_parts.append(f"STL geometry OK: {triangle_count:,} triangles")
    elif result.get("stl_file_exists"):
        feedback_parts.append(
            f"FAIL: STL invalid or insufficient geometry ({triangle_count:,} triangles, need >= {min_triangles:,})"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "measurement_count": result.get("measurement_count", 0),
            "measurements": result.get("measurements", []),
            "stl_triangle_count": result.get("stl_triangle_count", 0),
        },
    }
