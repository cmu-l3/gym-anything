#!/usr/bin/env python3
"""
Verifier for surface_mesh_optimization task.

Scoring (100 points total):
  - PLY file exists and is valid PLY format:      25 pts
  - PLY has >= 1,000 vertices (real geometry):    15 pts
  - STL file exists and is valid STL format:      25 pts
  - STL has >= 1,000 triangles (real geometry):   15 pts
  - Project file exists and is valid .inv3:       20 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_surface_mesh_optimization(traj, env_info, task_info):
    """Verify mesh optimization pipeline: smoothing + decimation + PLY + STL export."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_vertices = 1000
    min_triangles = metadata.get("min_triangle_count", 1000)

    score = 0
    feedback_parts = []

    # Copy result JSON from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/surface_mesh_optimization_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Independent re-analysis of PLY file ---
    ind_ply_valid = result.get("ply_valid", False)
    ind_ply_vertex_count = result.get("ply_vertex_count", 0)
    ind_ply_face_count = result.get("ply_face_count", 0)
    try:
        import re
        tmp_ply = tempfile.NamedTemporaryFile(delete=False, suffix=".ply")
        tmp_ply.close()
        try:
            copy_from_env("/home/ga/Documents/skull_optimized.ply", tmp_ply.name)
            with open(tmp_ply.name, "rb") as f:
                header_lines = []
                while True:
                    line = f.readline().decode("ascii", errors="replace").strip()
                    header_lines.append(line)
                    if line == "end_header":
                        break
                    if len(header_lines) > 200:
                        break
            header_text = "\n".join(header_lines)
            if header_lines and header_lines[0].lower() == "ply":
                ind_ply_valid = True
                vm = re.search(r"element vertex\s+(\d+)", header_text)
                if vm:
                    ind_ply_vertex_count = int(vm.group(1))
                fm = re.search(r"element face\s+(\d+)", header_text)
                if fm:
                    ind_ply_face_count = int(fm.group(1))
        finally:
            try:
                os.unlink(tmp_ply.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent PLY analysis failed: {e}")

    # --- Independent re-analysis of STL file ---
    import struct
    ind_stl_valid = result.get("stl_valid", False)
    ind_stl_triangles = result.get("stl_triangle_count", 0)
    try:
        tmp_stl = tempfile.NamedTemporaryFile(delete=False, suffix=".stl")
        tmp_stl.close()
        try:
            copy_from_env("/home/ga/Documents/skull_optimized.stl", tmp_stl.name)
            size = os.path.getsize(tmp_stl.name)
            if size >= 84:
                with open(tmp_stl.name, "rb") as f:
                    f.read(80)
                    cb = f.read(4)
                    if len(cb) == 4:
                        count = struct.unpack("<I", cb)[0]
                        if abs((80 + 4 + count * 50) - size) <= 512:
                            ind_stl_valid = True
                            ind_stl_triangles = count
            if not ind_stl_valid:
                with open(tmp_stl.name, "r", errors="replace") as f:
                    if f.readline().strip().lower().startswith("solid"):
                        count = sum(
                            1 for ln in f if ln.strip().lower().startswith("facet normal")
                        )
                        if count > 0:
                            ind_stl_valid = True
                            ind_stl_triangles = count
        finally:
            try:
                os.unlink(tmp_stl.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent STL analysis failed: {e}")

    # --- Criterion 1: PLY file valid (25 pts) ---
    if ind_ply_valid and result.get("ply_file_exists"):
        score += 25
        feedback_parts.append(
            f"skull_optimized.ply valid PLY ({ind_ply_vertex_count:,} vertices, "
            f"{ind_ply_face_count:,} faces)"
        )
    elif result.get("ply_file_exists"):
        score += 5
        feedback_parts.append("skull_optimized.ply exists but failed PLY validation")
    else:
        feedback_parts.append("FAIL: skull_optimized.ply not found at /home/ga/Documents/")

    # --- Criterion 2: PLY has >= 1,000 vertices (15 pts) ---
    if ind_ply_valid and ind_ply_vertex_count >= min_vertices:
        score += 15
        feedback_parts.append(f"PLY geometry OK: {ind_ply_vertex_count:,} vertices")
    elif ind_ply_valid:
        feedback_parts.append(
            f"FAIL: PLY only {ind_ply_vertex_count:,} vertices (need >= {min_vertices:,})"
        )

    # --- Criterion 3: STL file valid (25 pts) ---
    if ind_stl_valid and result.get("stl_file_exists"):
        score += 25
        feedback_parts.append(
            f"skull_optimized.stl valid STL ({ind_stl_triangles:,} triangles)"
        )
    elif result.get("stl_file_exists"):
        score += 5
        feedback_parts.append("skull_optimized.stl exists but failed STL validation")
    else:
        feedback_parts.append("FAIL: skull_optimized.stl not found at /home/ga/Documents/")

    # --- Criterion 4: STL has >= 1,000 triangles (15 pts) ---
    if ind_stl_valid and ind_stl_triangles >= min_triangles:
        score += 15
        feedback_parts.append(f"STL geometry OK: {ind_stl_triangles:,} triangles")
    elif ind_stl_valid:
        feedback_parts.append(
            f"FAIL: STL only {ind_stl_triangles:,} triangles (need >= {min_triangles:,})"
        )

    # --- Criterion 5: Project file exists and valid (20 pts) ---
    if result.get("project_file_exists") and result.get("project_valid_inv3"):
        score += 20
        feedback_parts.append("Project file saved and valid")
    elif result.get("project_file_exists"):
        score += 5
        feedback_parts.append("FAIL: Project exists but invalid .inv3 format")
    else:
        feedback_parts.append(
            "FAIL: Project not found at /home/ga/Documents/mesh_optimization.inv3"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "ply_vertex_count": ind_ply_vertex_count,
            "ply_face_count": ind_ply_face_count,
            "stl_triangle_count": ind_stl_triangles,
        },
    }
