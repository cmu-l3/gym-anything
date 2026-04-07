#!/usr/bin/env python3
"""
Verifier for NDT Surface Scan Path Generation task.

Scoring (100 points):
  - File Integrity (15 pts): Output files created dynamically after task start
  - Grid Completeness (15 pts): CSV contains >= 20 valid rows
  - Normal Vector Accuracy (25 pts): Exported surface normals match theoretical sphere normals
  - Tool Orientation Math (25 pts): Exported Euler angles correctly align tool -Z with surface normal
  - VLM Verification (20 pts): Visual confirmation of code/API workflow execution

Pass threshold: 70/100
"""

import os
import csv
import json
import math
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_col(headers, candidates):
    """Fuzzy column matcher."""
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        for idx, h in enumerate(hl):
            if c in h:
                return headers[idx]
    return None


def dot_prod(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))


def verify_ndt_surface_scan(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    feedback = []
    score = 0

    # 1. READ EXPORT METADATA
    tmp_meta = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_meta.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp_meta.name)
        with open(tmp_meta.name, "r") as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to read task export metadata."}
    finally:
        if os.path.exists(tmp_meta.name):
            os.unlink(tmp_meta.name)

    csv_ok = meta.get("csv_exists") and meta.get("csv_is_new")
    json_ok = meta.get("json_exists") and meta.get("json_is_new")

    if csv_ok and json_ok:
        score += 15
        feedback.append("Output files generated dynamically (+15)")
    elif csv_ok:
        score += 10
        feedback.append("Only CSV generated dynamically (partial: +10)")
    else:
        feedback.append("Required output files not found or pre-date task start.")

    # 2. FETCH AND PARSE CSV
    rows = []
    if meta.get("csv_exists"):
        tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
        tmp_csv.close()
        try:
            copy_from_env("/home/ga/Documents/CoppeliaSim/exports/scan_path.csv", tmp_csv.name)
            with open(tmp_csv.name, "r") as f:
                reader = csv.DictReader(f)
                rows = list(reader)
        except Exception as e:
            logger.warning(f"Failed to read CSV: {e}")
        finally:
            if os.path.exists(tmp_csv.name):
                os.unlink(tmp_csv.name)

    # 3. GEOMETRIC MATH VALIDATION
    valid_normals = 0
    valid_eulers = 0

    if rows:
        headers = list(rows[0].keys())
        col_hx = find_col(headers, ['hit_x', 'hx', 'x', 'pos_x'])
        col_hy = find_col(headers, ['hit_y', 'hy', 'y', 'pos_y'])
        col_hz = find_col(headers, ['hit_z', 'hz', 'z', 'pos_z'])
        col_nx = find_col(headers, ['normal_x', 'nx'])
        col_ny = find_col(headers, ['normal_y', 'ny'])
        col_nz = find_col(headers, ['normal_z', 'nz'])
        col_a = find_col(headers, ['alpha', 'roll', 'a', 'rx'])
        col_b = find_col(headers, ['beta', 'pitch', 'b', 'ry'])
        col_g = find_col(headers, ['gamma', 'yaw', 'g', 'rz'])

        if not all([col_hx, col_hy, col_hz, col_nx, col_ny, col_nz, col_a, col_b, col_g]):
            feedback.append("CSV is missing required coordinate or angle columns.")
        else:
            for row in rows:
                try:
                    hx, hy, hz = float(row[col_hx]), float(row[col_hy]), float(row[col_hz])
                    nx, ny, nz = float(row[col_nx]), float(row[col_ny]), float(row[col_nz])
                    a, b, g = float(row[col_a]), float(row[col_b]), float(row[col_g])

                    # Calculate theoretical Normal
                    hit_mag = math.sqrt(hx**2 + hy**2 + hz**2)
                    if hit_mag <= 0: continue
                    exp_nx, exp_ny, exp_nz = hx/hit_mag, hy/hit_mag, hz/hit_mag

                    # Verify Agent's Normal
                    rep_mag = math.sqrt(nx**2 + ny**2 + nz**2)
                    if rep_mag > 0:
                        rep_nx, rep_ny, rep_nz = nx/rep_mag, ny/rep_mag, nz/rep_mag
                        if dot_prod([exp_nx, exp_ny, exp_nz], [rep_nx, rep_ny, rep_nz]) > 0.95:
                            valid_normals += 1
                    
                    # Verify Euler Angles (Tait-Bryan XYZ intrinsic mapping to Z-axis)
                    # For R = Rx(a) Ry(b) Rz(g), Z_tool = [sin(b), -sin(a)cos(b), cos(a)cos(b)]
                    tool_z = [
                        math.sin(b),
                        -math.sin(a) * math.cos(b),
                        math.cos(a) * math.cos(b)
                    ]
                    
                    # Target: Z_tool should be anti-parallel to normal vector
                    if dot_prod(tool_z, [-exp_nx, -exp_ny, -exp_nz]) > 0.90:
                        valid_eulers += 1
                    # Grace criteria: Accept parallel (inwards) if they made a sign error
                    elif dot_prod(tool_z, [exp_nx, exp_ny, exp_nz]) > 0.90:
                        valid_eulers += 1

                except (ValueError, KeyError):
                    continue
    
    # Assess Grid Completeness (15 pts)
    row_count = len(rows)
    if row_count >= 20:
        score += 15
        feedback.append(f"Grid Complete: {row_count} waypoints logged (+15)")
    elif row_count >= 10:
        score += 7
        feedback.append(f"Grid Partial: {row_count} waypoints logged (partial: +7)")
    else:
        feedback.append(f"Insufficient grid size: {row_count} rows")

    # Assess Normal Accuracy (25 pts)
    if valid_normals >= 20:
        score += 25
        feedback.append("Surface normals perfectly align with theoretical sphere geometry (+25)")
    elif valid_normals >= 10:
        score += 12
        feedback.append(f"Partial normal vector accuracy ({valid_normals} correct) (partial: +12)")
    else:
        feedback.append("Surface normals are inaccurate or missing.")

    # Assess Tool Orientation Math (25 pts)
    if valid_eulers >= 20:
        score += 25
        feedback.append("Euler angles correctly orient the tool Z-axis orthogonal to the surface (+25)")
    elif valid_eulers >= 10:
        score += 12
        feedback.append(f"Partial tool orientation accuracy ({valid_eulers} correct) (partial: +12)")
    else:
        feedback.append("Euler angles fail to orient tool correctly against the surface.")

    # 4. VLM TRAJECTORY VERIFICATION (20 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = [img for img in frames + [final] if img]

        prompt = (
            "You are verifying a robotic simulation task. "
            "Did the agent use an IDE, terminal, or script editor to write/execute code "
            "(e.g., Python or Lua) to perform a programmatic surface scan in CoppeliaSim?\n"
            "Look for evidence of programming activity and simulation execution.\n"
            "Reply exactly with YES or NO."
        )

        vlm_res = query_vlm(images=images, prompt=prompt)
        if vlm_res and "YES" in vlm_res.get("response", "").upper():
            score += 20
            feedback.append("VLM verified programmatic simulation execution (+20)")
        else:
            feedback.append("VLM did not detect programmatic simulation scripting (0/20)")
    else:
        feedback.append("VLM query unavailable, skipping visual check.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }