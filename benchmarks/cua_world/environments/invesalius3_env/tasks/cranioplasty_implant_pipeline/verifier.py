#!/usr/bin/env python3
"""
Verifier for cranioplasty_implant_pipeline task.

A biomedical engineer chains two InVesalius capability areas in sequence:
  1. Boolean mask operations (full bone − compact bone → cancellous bone)
  2. Mesh optimisation (smoothing + decimation of compact bone surface)
Then exports PLY (optimised cortical) + STL (cancellous) + places 5+ measurements + saves project.

Scoring (100 points total):
  - Project file saved and valid:                              10 pts
  - >= 3 masks (full bone, compact, boolean result):          20 pts
  - PLY file valid (>= 1,000 vertices):                       25 pts
  - STL (cancellous bone) valid:                              20 pts
  - >= 5 measurements (all >= 10 mm):                         15 pts
  - PLY face count < 400,000 (decimation applied):            10 pts

Pass threshold: 65 points

GATE: No PLY AND no STL AND no project → score = 0.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_cranioplasty_implant_pipeline(traj, env_info, task_info):
    """Verify cranioplasty implant pipeline: boolean ops + mesh optimization + PLY + STL."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    req_mask_count     = metadata.get("required_mask_count", 3)
    max_ply_triangles  = metadata.get("max_ply_triangles", 400000)
    min_ply_vertices   = metadata.get("min_ply_vertices", 1000)
    req_measurements   = metadata.get("required_measurement_count", 5)
    min_meas_mm        = metadata.get("min_measurement_mm", 10.0)

    score = 0
    feedback_parts = []

    # ── Copy result JSON ──────────────────────────────────────────────────────
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/cranioplasty_implant_pipeline_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}

    # ── OUTPUT-EXISTENCE GATE ─────────────────────────────────────────────────
    has_ply     = result.get("ply_exists", False)
    has_stl     = result.get("stl_exists", False)
    has_project = result.get("project_file_exists", False)
    if not has_ply and not has_stl and not has_project:
        return {"passed": False, "score": 0, "feedback": "No output files found (do-nothing baseline)"}

    # ── Independent re-analysis of .inv3 ─────────────────────────────────────
    ind_mask_count        = result.get("mask_count", 0)
    ind_measurement_count = result.get("measurement_count", 0)
    ind_measurements      = [m["value_mm"] for m in result.get("measurements", [])]
    ind_masks_detail      = result.get("masks_detail", [])

    try:
        import tarfile, plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        copy_from_env("/home/ga/Documents/cranioplasty/implant_fabrication.inv3", tmp_inv3.name)
        try:
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                mask_plists = {}
                for member in t.getmembers():
                    bname = os.path.basename(member.name)
                    if bname == "main.plist":
                        f = t.extractfile(member)
                        main = plistlib.load(f)
                        cnt = len(main.get("masks", {}))
                        if cnt > ind_mask_count:
                            ind_mask_count = cnt
                    elif bname.startswith("mask_") and bname.endswith(".plist"):
                        f = t.extractfile(member)
                        mask_plists[bname] = plistlib.load(f)
                    elif bname == "measurements.plist":
                        f = t.extractfile(member)
                        md = plistlib.load(f)
                        if len(md) > ind_measurement_count:
                            ind_measurement_count = len(md)
                            ind_measurements = [float(m.get("value", 0)) for m in md.values()]

                ind_masks_detail = []
                for name, mp in mask_plists.items():
                    tr = mp.get("threshold_range", [0, 0])
                    min_hu = float(tr[0]) if len(tr) >= 1 else 0.0
                    max_hu = float(tr[1]) if len(tr) >= 2 else 0.0
                    ind_masks_detail.append({"min_hu": min_hu, "max_hu": max_hu})
        finally:
            try:
                os.unlink(tmp_inv3.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent .inv3 re-analysis failed: {e}")

    # Independent PLY re-analysis
    ind_ply_vertices = result.get("ply_vertex_count", 0)
    ind_ply_faces    = result.get("ply_face_count", 0)
    ind_ply_valid    = result.get("ply_valid", False)
    try:
        tmp_ply = tempfile.NamedTemporaryFile(delete=False, suffix=".ply")
        tmp_ply.close()
        copy_from_env("/home/ga/Documents/cranioplasty/cortical_bone.ply", tmp_ply.name)
        try:
            with open(tmp_ply.name, "rb") as f:
                header_raw = f.read(2048)
            header_text = header_raw.decode("ascii", errors="replace")
            lines = header_text.splitlines()
            if lines and lines[0].strip().lower().startswith("ply"):
                ind_ply_valid = True
                for line in lines:
                    vm = re.match(r"element\s+vertex\s+(\d+)", line.strip(), re.IGNORECASE)
                    if vm:
                        v = int(vm.group(1))
                        if v > ind_ply_vertices:
                            ind_ply_vertices = v
                    fm = re.match(r"element\s+face\s+(\d+)", line.strip(), re.IGNORECASE)
                    if fm:
                        f2 = int(fm.group(1))
                        if f2 > ind_ply_faces:
                            ind_ply_faces = f2
        finally:
            try:
                os.unlink(tmp_ply.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent PLY re-analysis failed: {e}")

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

    # ── Criterion 2: >= 3 masks (20 pts) ──────────────────────────────────────
    try:
        mcount = ind_mask_count
        has_full_bone    = any(m["min_hu"] <= 280 and m["max_hu"] >= 2000 for m in ind_masks_detail)
        has_compact_bone = any(m["min_hu"] >= 600 for m in ind_masks_detail)
        if mcount >= req_mask_count:
            score += 20
            bonus_info = ""
            if has_full_bone and has_compact_bone:
                bonus_info = " (full bone + compact bone + boolean result confirmed)"
            feedback_parts.append(f"{mcount} masks found{bonus_info}")
        elif mcount == 2:
            score += 10
            feedback_parts.append(f"Partial: 2 masks found (need {req_mask_count} including boolean result)")
        elif mcount == 1:
            score += 4
            feedback_parts.append("Only 1 mask found — boolean operation likely not performed")
        else:
            feedback_parts.append("FAIL: No masks found in project")
    except Exception as e:
        feedback_parts.append(f"Mask count check error: {e}")

    # ── Criterion 3: PLY file valid (>= 1,000 vertices) (25 pts) ─────────────
    try:
        if ind_ply_valid and ind_ply_vertices >= min_ply_vertices:
            score += 25
            feedback_parts.append(
                f"PLY valid: {ind_ply_vertices:,} vertices, {ind_ply_faces:,} faces"
            )
        elif ind_ply_valid:
            score += 10
            feedback_parts.append(
                f"PLY format valid but only {ind_ply_vertices:,} vertices "
                f"(need >= {min_ply_vertices:,})"
            )
        elif result.get("ply_exists"):
            score += 4
            feedback_parts.append("PLY file exists but not valid PLY format")
        else:
            feedback_parts.append("FAIL: PLY file not found at /home/ga/Documents/cranioplasty/cortical_bone.ply")
    except Exception as e:
        feedback_parts.append(f"PLY check error: {e}")

    # ── Criterion 4: STL (cancellous bone) valid (20 pts) ─────────────────────
    try:
        if result.get("stl_valid"):
            score += 20
            tri = result.get("stl_triangle_count", 0)
            feedback_parts.append(f"Cancellous bone STL valid: {tri:,} triangles")
        elif result.get("stl_exists"):
            score += 6
            feedback_parts.append("STL file exists but not valid STL format")
        else:
            feedback_parts.append("FAIL: STL not found at /home/ga/Documents/cranioplasty/cancellous_bone.stl")
    except Exception as e:
        feedback_parts.append(f"STL check error: {e}")

    # ── Criterion 5: >= 5 measurements (all >= 10 mm) (15 pts) ───────────────
    try:
        meas_count = ind_measurement_count
        above_min  = sum(1 for v in ind_measurements if v >= min_meas_mm)
        if meas_count >= req_measurements and above_min >= req_measurements:
            score += 15
            feedback_parts.append(f"{meas_count} measurements, all >= {min_meas_mm} mm")
        elif meas_count >= req_measurements:
            score += 8
            feedback_parts.append(
                f"{meas_count} measurements but only {above_min} >= {min_meas_mm} mm"
            )
        elif meas_count > 0:
            pts = int(15 * meas_count / req_measurements)
            score += pts
            feedback_parts.append(f"Partial: {meas_count}/{req_measurements} measurements ({pts} pts)")
        else:
            feedback_parts.append("FAIL: No measurements found")
    except Exception as e:
        feedback_parts.append(f"Measurement check error: {e}")

    # ── Criterion 6: PLY face count < 400,000 (decimation applied) (10 pts) ──
    try:
        if ind_ply_valid and 0 < ind_ply_faces < max_ply_triangles:
            score += 10
            feedback_parts.append(
                f"Decimation applied: {ind_ply_faces:,} faces < {max_ply_triangles:,} limit"
            )
        elif ind_ply_valid and ind_ply_faces >= max_ply_triangles:
            feedback_parts.append(
                f"FAIL: PLY has {ind_ply_faces:,} faces — decimation not applied "
                f"(need < {max_ply_triangles:,})"
            )
        elif ind_ply_valid and ind_ply_faces == 0:
            feedback_parts.append("PLY face count not determinable from header")
        # else: PLY invalid — already handled above
    except Exception as e:
        feedback_parts.append(f"Decimation check error: {e}")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "mask_count":           ind_mask_count,
            "ply_vertices":         ind_ply_vertices,
            "ply_faces":            ind_ply_faces,
            "stl_triangles":        result.get("stl_triangle_count", 0),
            "measurement_count":    ind_measurement_count,
        },
    }
