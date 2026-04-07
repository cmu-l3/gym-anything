"""
Verifier for openvsp_multi_format_export task.

Checks that three export files were produced from eCRM-001:
  1. eCRM001_mesh.stl — STL triangulated surface (ASCII or binary)
  2. eCRM001_cart3d.tri — Cart3D triangulated surface (text header)
  3. eCRM001_degengeom.csv — Degen Geom CSV (comma-separated with header)

Scoring (100 points total):
  - STL file exists with valid STL signature: 33 pts
  - Cart3D .tri file exists with valid header: 34 pts
  - Degen Geom CSV exists with valid content: 33 pts

Pass threshold: 67 (at least 2 of 3 exports correct).
"""

import json
import os
import tempfile


def _check_stl(info: dict) -> tuple[bool, str]:
    """Validate STL file content."""
    if not info.get("exists"):
        return False, "STL file does not exist."
    if info.get("size", 0) < 100:
        return False, f"STL file too small ({info.get('size', 0)} bytes) — likely empty."
    first_line = info.get("first_line", "").lower().strip()
    first_bytes_hex = info.get("first_bytes_hex", "")
    # ASCII STL starts with "solid"
    if first_line.startswith("solid"):
        return True, f"Valid ASCII STL (starts with 'solid'), size={info['size']} bytes."
    # Binary STL: 80-byte header, no magic — just check size >= 284 bytes (1 triangle minimum)
    if info.get("size", 0) >= 284:
        return True, f"Valid binary STL (size={info['size']} bytes)."
    return False, f"STL file content unrecognized (first_line={first_line!r})."


def _check_tri(info: dict) -> tuple[bool, str]:
    """Validate Cart3D .tri file content."""
    if not info.get("exists"):
        return False, "Cart3D .tri file does not exist."
    if info.get("size", 0) < 50:
        return False, f"Cart3D file too small ({info.get('size', 0)} bytes)."
    first_line = info.get("first_line", "").strip()
    # Cart3D .tri format: first line is "<nNodes> <nTris>" — two integers
    parts = first_line.split()
    if len(parts) >= 2:
        try:
            n_nodes = int(parts[0])
            n_tris = int(parts[1])
            if n_nodes > 0 and n_tris > 0:
                return True, f"Valid Cart3D .tri (nodes={n_nodes}, tris={n_tris}), size={info['size']} bytes."
        except ValueError:
            pass
    return False, f"Cart3D file first line not a valid header: {first_line!r}."


def _check_csv(info: dict) -> tuple[bool, str]:
    """Validate Degen Geom CSV content."""
    if not info.get("exists"):
        return False, "Degen Geom CSV does not exist."
    if info.get("size", 0) < 50:
        return False, f"Degen Geom CSV too small ({info.get('size', 0)} bytes)."
    first_line = info.get("first_line", "").strip()
    # Degen Geom CSV starts with "# DegenGeom" comment header
    if first_line.startswith("#") or "," in first_line or "Comp" in first_line or "degen" in first_line.lower():
        return True, f"Valid Degen Geom CSV (first_line={first_line[:50]!r}), size={info['size']} bytes."
    return False, f"Degen Geom CSV unrecognized first line: {first_line!r}."


def verify_openvsp_multi_format_export(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_multi_format_export_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}",
        }

    with open(local_tmp, "r") as f:
        data = json.load(f)
    os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # Check STL (33 pts)
    stl_ok, stl_msg = _check_stl(data.get("stl", {}))
    if stl_ok:
        score += 33
        feedback_parts.append(f"STL: {stl_msg} (+33)")
    else:
        feedback_parts.append(f"STL: {stl_msg} (+0)")

    # Check Cart3D .tri (34 pts)
    tri_ok, tri_msg = _check_tri(data.get("tri", {}))
    if tri_ok:
        score += 34
        feedback_parts.append(f"Cart3D: {tri_msg} (+34)")
    else:
        feedback_parts.append(f"Cart3D: {tri_msg} (+0)")

    # Check Degen Geom CSV (33 pts)
    csv_ok, csv_msg = _check_csv(data.get("csv", {}))
    if csv_ok:
        score += 33
        feedback_parts.append(f"DegenGeom: {csv_msg} (+33)")
    else:
        feedback_parts.append(f"DegenGeom: {csv_msg} (+0)")

    passed = score >= 67
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
