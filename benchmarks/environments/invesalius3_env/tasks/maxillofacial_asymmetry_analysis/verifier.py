#!/usr/bin/env python3
"""
Verifier for maxillofacial_asymmetry_analysis task.

An oral and maxillofacial surgeon performs a comprehensive bilateral symmetry
workup for orthognathic surgery: >= 12 measurements (bilateral protocol),
3D bone surface STL export, and 5 orientation screenshots (anterior, left
lateral, right lateral, superior, posterior).

This is the highest-complexity task in the invesalius3_env environment.

Scoring (100 points total):
  - Project file saved and valid:                   10 pts
  - >= 12 measurements in project:                 25 pts
  - All measurements >= 10 mm:                     10 pts
  - STL file valid (>= 10,000 triangles):          20 pts
  - anterior_view.png valid (>= 10 KB):             7 pts
  - left_lateral.png valid (>= 10 KB):              7 pts
  - right_lateral.png valid (>= 10 KB):             7 pts
  - superior_view.png valid (>= 10 KB):             7 pts
  - posterior_view.png valid (>= 10 KB):            7 pts

Pass threshold: 65 points

GATE: No project AND no STL AND no PNGs → score = 0 immediately.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])


def _check_png_local(path):
    try:
        if not os.path.isfile(path):
            return False, 0
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            magic = f.read(8)
        return magic == PNG_MAGIC, size
    except Exception:
        return False, 0


def verify_maxillofacial_asymmetry_analysis(traj, env_info, task_info):
    """Verify maxillofacial asymmetry analysis: 12+ measurements + STL + 5 orientation PNGs."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    required_measurements = metadata.get("required_measurement_count", 12)
    min_measurement_mm    = metadata.get("min_measurement_mm", 10.0)
    min_stl_triangles     = metadata.get("min_stl_triangles", 10000)
    min_png_bytes         = metadata.get("min_png_size_bytes", 10240)

    score = 0
    feedback_parts = []

    # ── Copy result JSON ──────────────────────────────────────────────────────
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/maxillofacial_asymmetry_analysis_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}

    # ── OUTPUT-EXISTENCE GATE ─────────────────────────────────────────────────
    has_project = result.get("project_file_exists", False)
    has_stl     = result.get("stl", {}).get("exists", False)
    png_keys    = ("anterior_view", "left_lateral", "right_lateral", "superior_view", "posterior_view")
    has_any_png = any(result.get(f"png_{k}", {}).get("exists", False) for k in png_keys)
    if not has_project and not has_stl and not has_any_png:
        return {"passed": False, "score": 0, "feedback": "No output files found (do-nothing baseline)"}

    # ── Independent re-analysis of .inv3 ─────────────────────────────────────
    ind_measurement_count = result.get("measurement_count", 0)
    ind_measurements      = [m["value_mm"] for m in result.get("measurements", [])]

    try:
        import tarfile, plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        copy_from_env(
            "/home/ga/Documents/asymmetry_study/asymmetry_analysis.inv3",
            tmp_inv3.name,
        )
        try:
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                for member in t.getmembers():
                    bname = os.path.basename(member.name)
                    if bname == "measurements.plist":
                        f = t.extractfile(member)
                        meas_dict = plistlib.load(f)
                        if len(meas_dict) > ind_measurement_count:
                            ind_measurement_count = len(meas_dict)
                            ind_measurements = [
                                float(m.get("value", 0)) for m in meas_dict.values()
                            ]
        finally:
            try:
                os.unlink(tmp_inv3.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent .inv3 re-analysis failed: {e}")

    # ── Criterion 1: Project file saved and valid (10 pts) ───────────────────
    try:
        if result.get("project_file_exists") and result.get("project_valid_inv3"):
            score += 10
            feedback_parts.append("Project file valid")
        elif result.get("project_file_exists"):
            score += 3
            feedback_parts.append("Project file exists but not parseable as .inv3")
        else:
            feedback_parts.append("FAIL: Project file not found")
    except Exception as e:
        feedback_parts.append(f"Project check error: {e}")

    # ── Criterion 2: >= 12 measurements (25 pts) ──────────────────────────────
    try:
        mcount = ind_measurement_count
        if mcount >= required_measurements:
            score += 25
            feedback_parts.append(f"{mcount} measurements found (need >= {required_measurements})")
        elif mcount >= 8:
            pts = int(25 * mcount / required_measurements)
            score += pts
            feedback_parts.append(
                f"Partial: {mcount}/{required_measurements} measurements ({pts} pts)"
            )
        elif mcount > 0:
            pts = max(0, int(25 * mcount / required_measurements))
            score += pts
            feedback_parts.append(
                f"Partial: only {mcount} measurements placed ({pts} pts)"
            )
        else:
            feedback_parts.append("FAIL: No measurements found in project")
    except Exception as e:
        feedback_parts.append(f"Measurement count error: {e}")

    # ── Criterion 3: All measurements >= 10 mm (10 pts) ──────────────────────
    try:
        if ind_measurements:
            above_min = sum(1 for v in ind_measurements if v >= min_measurement_mm)
            if above_min >= required_measurements:
                score += 10
                feedback_parts.append(f"All {above_min} measurements >= {min_measurement_mm} mm")
            elif above_min >= ind_measurement_count * 0.8:
                score += 5
                feedback_parts.append(
                    f"{above_min}/{len(ind_measurements)} measurements >= {min_measurement_mm} mm"
                )
            else:
                feedback_parts.append(
                    f"FAIL: Only {above_min}/{len(ind_measurements)} measurements >= {min_measurement_mm} mm"
                )
    except Exception as e:
        feedback_parts.append(f"Measurement value check error: {e}")

    # ── Criterion 4: STL file valid (>= 10,000 triangles) (20 pts) ───────────
    try:
        stl_info = result.get("stl", {})
        if stl_info.get("valid") and stl_info.get("triangle_count", 0) >= min_stl_triangles:
            score += 20
            feedback_parts.append(
                f"STL valid: {stl_info['triangle_count']:,} triangles"
            )
        elif stl_info.get("valid"):
            score += 8
            feedback_parts.append(
                f"STL valid but only {stl_info.get('triangle_count', 0):,} triangles "
                f"(need >= {min_stl_triangles:,})"
            )
        elif stl_info.get("exists"):
            score += 3
            feedback_parts.append("STL file exists but not valid STL format")
        else:
            feedback_parts.append("FAIL: STL not found at /home/ga/Documents/asymmetry_study/skull_model.stl")
    except Exception as e:
        feedback_parts.append(f"STL check error: {e}")

    # ── Criteria 5–9: Five orientation PNGs (7 pts each = 35 pts) ─────────────
    png_specs = [
        ("anterior_view",  "Anterior view",       "/home/ga/Documents/asymmetry_study/anterior_view.png"),
        ("left_lateral",   "Left lateral view",   "/home/ga/Documents/asymmetry_study/left_lateral.png"),
        ("right_lateral",  "Right lateral view",  "/home/ga/Documents/asymmetry_study/right_lateral.png"),
        ("superior_view",  "Superior view",       "/home/ga/Documents/asymmetry_study/superior_view.png"),
        ("posterior_view", "Posterior view",      "/home/ga/Documents/asymmetry_study/posterior_view.png"),
    ]

    for key, label, remote_path in png_specs:
        try:
            export_info = result.get(f"png_{key}", {})
            # Independent copy + verify
            try:
                tmp_png = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
                tmp_png.close()
                copy_from_env(remote_path, tmp_png.name)
                valid, size = _check_png_local(tmp_png.name)
                os.unlink(tmp_png.name)
            except Exception:
                valid = export_info.get("valid_png", False)
                size  = export_info.get("size_bytes", 0)

            if valid and size >= min_png_bytes:
                score += 7
                feedback_parts.append(f"{label} PNG valid ({size // 1024} KB)")
            elif export_info.get("exists"):
                feedback_parts.append(
                    f"FAIL: {label} PNG exists but invalid or too small ({size} bytes)"
                )
            else:
                feedback_parts.append(f"FAIL: {label} PNG not found")
        except Exception as e:
            feedback_parts.append(f"{label} PNG check error: {e}")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "measurement_count": ind_measurement_count,
            "stl_triangles":     result.get("stl", {}).get("triangle_count", 0),
            "png_count_valid":   sum(
                1 for k, _, rp in png_specs
                if result.get(f"png_{k}", {}).get("valid_png", False)
            ),
        },
    }
