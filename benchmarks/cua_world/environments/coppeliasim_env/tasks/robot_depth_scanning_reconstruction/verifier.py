#!/usr/bin/env python3
"""
Verifier for robot_depth_scanning_reconstruction task.

Scoring (100 points):
  - Criterion 1: File Generation (15 pts). `merged_pointcloud.csv`, `scanning_report.json`, and >= 4 `depth_view_*.csv` exist and are new.
  - Criterion 2: Raw Depth Validity (20 pts). The raw depth CSVs contain valid normalized float data with variance > 0 (proving it saw an object).
  - Criterion 3: Metadata Integrity (20 pts). JSON contains >= 4 distinct pose matrices.
  - Criterion 4: Point Cloud Completeness (20 pts). Merged CSV contains >= 500 valid 3D points.
  - Criterion 5: Geometric Accuracy (25 pts). The point cloud centroid mathematically aligns with the target zone (X ~ 0.5, Y ~ 0.0), proving successful multi-view 3D projection.

Pass threshold: 75
Anti-gaming:
  - Do-nothing score: 0
  - Random point cloud injection: fails Criterion 2 (raw depth variance checks).
  - Bad coordinate math: fails Criterion 5 (centroid outside physical workspace).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/robot_depth_scanning_result.json"


def verify_robot_depth_scanning(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Safe gets
    merged_exists = result.get("merged_csv_exists", False)
    merged_new = result.get("merged_csv_is_new", False)
    report_exists = result.get("report_json_exists", False)
    report_new = result.get("report_json_is_new", False)
    depth_new_count = result.get("depth_csvs_new_count", 0)
    depth_valid_count = result.get("depth_valid_count", 0)
    num_poses = result.get("num_poses_in_json", 0)
    pc_num_points = result.get("pc_num_points", 0)
    pc_centroid = result.get("pc_centroid", None)

    # Criterion 1: File Generation (15 pts)
    if merged_exists and merged_new and report_exists and report_new and depth_new_count >= 4:
        score += 15
        feedback.append(f"All required output files generated including {depth_new_count} depth views (+15)")
    elif merged_exists and report_exists:
        score += 5
        feedback.append(f"Output files exist but might be incomplete/stale (views: {depth_new_count}) (partial: 5/15)")
    else:
        feedback.append("Missing core output files (merged point cloud, report, or depth views)")

    # Criterion 2: Raw Depth Validity (20 pts)
    if depth_valid_count >= 4:
        score += 20
        feedback.append(f"Raw depth variance verified across {depth_valid_count} views (sensor detected an object) (+20)")
    elif depth_valid_count > 0:
        score += 10
        feedback.append(f"Raw depth variance verified in only {depth_valid_count} views (partial: 10/20)")
    else:
        feedback.append("No valid raw depth variance detected (sensors only saw background/clipping plane)")

    # Criterion 3: Metadata Integrity (20 pts)
    if num_poses >= 4:
        score += 20
        feedback.append(f"Report JSON contains {num_poses} pose matrices (>= 4 required) (+20)")
    elif num_poses > 0:
        score += 10
        feedback.append(f"Report JSON contains {num_poses} pose matrices (partial: 10/20)")
    else:
        feedback.append("Report JSON lacks distinct pose matrices for the views")

    # Criterion 4: Point Cloud Completeness (20 pts)
    if pc_num_points >= 500:
        score += 20
        feedback.append(f"Merged point cloud contains {pc_num_points} points (>= 500 required) (+20)")
    elif pc_num_points >= 100:
        score += 10
        feedback.append(f"Merged point cloud contains {pc_num_points} points (partial: 10/20)")
    else:
        feedback.append(f"Merged point cloud lacks sufficient points ({pc_num_points})")

    # Criterion 5: Geometric Accuracy (25 pts)
    if pc_centroid is not None and len(pc_centroid) == 3:
        cx, cy, cz = pc_centroid
        # Target zone tolerances (X ~ 0.5, Y ~ 0.0, Z > 0.0)
        x_valid = 0.1 <= cx <= 0.9
        y_valid = -0.5 <= cy <= 0.5
        z_valid = cz > -0.1
        
        if x_valid and y_valid and z_valid:
            score += 25
            feedback.append(f"Point cloud centroid [{cx:.2f}, {cy:.2f}, {cz:.2f}] aligns accurately with target workspace (+25)")
        else:
            score += 5
            feedback.append(f"Point cloud centroid [{cx:.2f}, {cy:.2f}, {cz:.2f}] is outside expected target zone. Coordinate math may be incorrect (partial: 5/25)")
    else:
        feedback.append("Could not compute point cloud centroid. Missing valid world_x, world_y, world_z columns.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }