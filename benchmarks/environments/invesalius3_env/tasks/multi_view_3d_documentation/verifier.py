#!/usr/bin/env python3
"""
Verifier for multi_view_3d_documentation task.

Scoring (100 points total):
  - Project file exists and is valid .inv3:                  20 pts
  - >= 3 measurements, all >= 30 mm:                        25 pts
  - anterior_view.png exists and is valid PNG (>= 10 KB):   15 pts
  - lateral_view.png exists and is valid PNG (>= 10 KB):    20 pts
  - superior_view.png exists and is valid PNG (>= 10 KB):   20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])


def _check_png_from_env(copy_from_env, vm_path, min_size=10240):
    """Copy a PNG from the VM and validate it."""
    info = {"exists": False, "valid_png": False, "size_bytes": 0}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        tmp.close()
        try:
            copy_from_env(vm_path, tmp.name)
            if os.path.isfile(tmp.name):
                info["size_bytes"] = os.path.getsize(tmp.name)
                info["exists"] = info["size_bytes"] > 0
                if info["size_bytes"] >= 8:
                    with open(tmp.name, "rb") as f:
                        magic = f.read(8)
                    info["valid_png"] = (magic == PNG_MAGIC)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"PNG check failed for {vm_path}: {e}")
    return info


def verify_multi_view_3d_documentation(traj, env_info, task_info):
    """Verify surgical documentation: 3D screenshots from 3 views + measurements + project."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    required_measurements = metadata.get("required_measurement_count", 3)
    min_measurement_mm = metadata.get("min_measurement_value_mm", 30.0)
    min_png_size = metadata.get("min_png_size_bytes", 10240)

    score = 0
    feedback_parts = []

    # Copy result JSON from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/multi_view_3d_documentation_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: Project file saved and valid (20 pts) ---
    if result.get("project_file_exists") and result.get("project_valid_inv3"):
        score += 20
        feedback_parts.append("Project file saved and valid")
    elif result.get("project_file_exists"):
        score += 5
        feedback_parts.append("FAIL: Project exists but invalid .inv3 format")
    else:
        feedback_parts.append(
            "FAIL: Project not found at /home/ga/Documents/surgical_views/skull_study.inv3"
        )

    # Independent measurement verification: copy .inv3 and re-parse
    ind_measurement_count = result.get("measurement_count", 0)
    ind_above_30 = result.get("measurements_above_30mm", 0)
    try:
        import tarfile
        import plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        try:
            copy_from_env(
                "/home/ga/Documents/surgical_views/skull_study.inv3",
                tmp_inv3.name,
            )
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                for member in t.getmembers():
                    if os.path.basename(member.name) == "measurements.plist":
                        f = t.extractfile(member)
                        meas_dict = plistlib.load(f)
                        ind_measurement_count = len(meas_dict)
                        values = [float(m.get("value", 0)) for m in meas_dict.values()]
                        ind_above_30 = sum(1 for v in values if v >= min_measurement_mm)
                        break
        finally:
            try:
                os.unlink(tmp_inv3.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent .inv3 analysis failed: {e}")

    # --- Criterion 2: >= 3 measurements, all >= 30 mm (25 pts) ---
    if ind_measurement_count >= required_measurements and ind_above_30 >= required_measurements:
        score += 25
        feedback_parts.append(
            f"{ind_measurement_count} measurements found, {ind_above_30} >= {min_measurement_mm} mm"
        )
    elif ind_measurement_count >= required_measurements:
        score += 10
        feedback_parts.append(
            f"FAIL: {ind_measurement_count} measurements but only {ind_above_30} >= {min_measurement_mm} mm"
        )
    elif ind_measurement_count > 0:
        feedback_parts.append(
            f"FAIL: Only {ind_measurement_count} measurement(s), need >= {required_measurements}"
        )
    else:
        feedback_parts.append("FAIL: No measurements found in project")

    # --- Criterion 3: anterior_view.png (15 pts) ---
    ant_info = _check_png_from_env(
        copy_from_env,
        "/home/ga/Documents/surgical_views/anterior_view.png",
        min_png_size,
    )
    if ant_info.get("valid_png") and ant_info.get("size_bytes", 0) >= min_png_size:
        score += 15
        feedback_parts.append(
            f"anterior_view.png valid PNG ({ant_info['size_bytes'] // 1024} KB)"
        )
    elif ant_info.get("exists"):
        score += 5
        feedback_parts.append(
            f"anterior_view.png exists but too small or invalid "
            f"({ant_info.get('size_bytes', 0)} bytes)"
        )
    else:
        feedback_parts.append("FAIL: anterior_view.png not found")

    # --- Criterion 4: lateral_view.png (20 pts) ---
    lat_info = _check_png_from_env(
        copy_from_env,
        "/home/ga/Documents/surgical_views/lateral_view.png",
        min_png_size,
    )
    if lat_info.get("valid_png") and lat_info.get("size_bytes", 0) >= min_png_size:
        score += 20
        feedback_parts.append(
            f"lateral_view.png valid PNG ({lat_info['size_bytes'] // 1024} KB)"
        )
    elif lat_info.get("exists"):
        score += 5
        feedback_parts.append(
            f"lateral_view.png exists but too small or invalid "
            f"({lat_info.get('size_bytes', 0)} bytes)"
        )
    else:
        feedback_parts.append("FAIL: lateral_view.png not found")

    # --- Criterion 5: superior_view.png (20 pts) ---
    sup_info = _check_png_from_env(
        copy_from_env,
        "/home/ga/Documents/surgical_views/superior_view.png",
        min_png_size,
    )
    if sup_info.get("valid_png") and sup_info.get("size_bytes", 0) >= min_png_size:
        score += 20
        feedback_parts.append(
            f"superior_view.png valid PNG ({sup_info['size_bytes'] // 1024} KB)"
        )
    elif sup_info.get("exists"):
        score += 5
        feedback_parts.append(
            f"superior_view.png exists but too small or invalid "
            f"({sup_info.get('size_bytes', 0)} bytes)"
        )
    else:
        feedback_parts.append("FAIL: superior_view.png not found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "measurement_count": ind_measurement_count,
            "measurements_above_30mm": ind_above_30,
            "anterior_png_size": ant_info.get("size_bytes", 0),
            "lateral_png_size": lat_info.get("size_bytes", 0),
            "superior_png_size": sup_info.get("size_bytes", 0),
        },
    }
