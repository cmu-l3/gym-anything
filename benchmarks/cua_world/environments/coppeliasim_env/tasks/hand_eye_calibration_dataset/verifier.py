#!/usr/bin/env python3
"""
Verifier for hand_eye_calibration_dataset task.

Scoring System (100 points, Pass >= 80):
- 15 pts: Files exist and were created after the task started (anti-gaming).
- 15 pts: CSV contains >= 20 rows and all 14 required columns.
- 20 pts: Spatial diversity (End-effector actually moved through a wide volume).
- 50 pts: Rigid Body Constraint. The relative transformation M_{ee}^{cam} MUST be
          constant across all 20+ samples. This mathematically proves the agent
          actually attached the sensor and accurately polled the simulation rather
          than hallucinating or generating fake kinematics data.
"""

import json
import tempfile
import os
import csv
import logging
import numpy as np

logger = logging.getLogger(__name__)


def quat_to_mat(q):
    """Convert a quaternion [x, y, z, w] to a 3x3 rotation matrix."""
    x, y, z, w = q
    n = x*x + y*y + z*z + w*w
    if n == 0:
        return np.eye(3)
    s = 2.0 / n
    wx, wy, wz = w*x*s, w*y*s, w*z*s
    xx, xy, xz = x*x*s, x*y*s, x*z*s
    yy, yz, zz = y*y*s, y*z*s, z*z*s

    return np.array([
        [1.0 - (yy + zz), xy - wz, xz + wy],
        [xy + wz, 1.0 - (xx + zz), yz - wx],
        [xz - wy, yz + wx, 1.0 - (xx + yy)]
    ])

def pose_to_matrix(pos, quat):
    """Convert position and quaternion to a 4x4 homogeneous transformation matrix."""
    T = np.eye(4)
    T[:3, :3] = quat_to_mat(quat)
    T[:3, 3] = pos
    return T

def matrix_inv(T):
    """Analytic inverse of a 4x4 homogeneous transformation matrix."""
    T_inv = np.eye(4)
    R_T = T[:3, :3].T
    T_inv[:3, :3] = R_T
    T_inv[:3, 3] = -R_T @ T[:3, 3]
    return T_inv


def verify_hand_eye_dataset(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    required_cols = metadata.get("expected_columns", [])

    score = 0
    feedback = []

    # 1. Copy the export result metadata
    meta_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    meta_tmp.close()
    
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    csv_tmp.close()
    
    json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    json_tmp.close()

    try:
        copy_from_env("/tmp/hand_eye_task_result.json", meta_tmp.name)
        with open(meta_tmp.name, "r") as f:
            export_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task metadata: {e}"}

    # CRITERION 1: File Existence & Timestamps (15 points)
    task_start_ts = export_meta.get("task_start_ts", 0)
    csv_exists = export_meta.get("csv_exists", False)
    json_exists = export_meta.get("json_exists", False)
    csv_mtime = export_meta.get("csv_mtime", 0)
    json_mtime = export_meta.get("json_mtime", 0)

    if csv_exists and json_exists and csv_mtime > task_start_ts and json_mtime > task_start_ts:
        score += 15
        feedback.append("Files exist and were created during task (+15)")
    else:
        feedback.append("Files missing or stale. Did not complete file generation.")
        # Cannot proceed without files
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Copy actual data files from the environment
    try:
        copy_from_env("/home/ga/Documents/CoppeliaSim/exports/hand_eye_dataset.csv", csv_tmp.name)
        copy_from_env("/home/ga/Documents/CoppeliaSim/exports/dataset_report.json", json_tmp.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to extract dataset files: {e}"}

    # CRITERION 2: Proper Dimensions (15 points)
    try:
        with open(csv_tmp.name, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        headers = reader.fieldnames if reader.fieldnames else []
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"CSV parse error: {e}"}

    has_all_cols = all(col in headers for col in required_cols)
    row_count = len(rows)

    if has_all_cols and row_count >= 20:
        score += 15
        feedback.append(f"CSV has correct schema and {row_count} rows (+15)")
    else:
        if not has_all_cols:
            feedback.append("CSV is missing required pose columns.")
        if row_count < 20:
            feedback.append(f"CSV only has {row_count}/20 required rows.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Parse JSON report
    try:
        with open(json_tmp.name, "r") as f:
            report_data = json.load(f)
        if "ee_handle" in report_data and "camera_handle" in report_data:
            pass # good
    except Exception:
        feedback.append("JSON report is malformed or missing fields.")

    # Data extraction for math checks
    try:
        ee_pos = []
        ee_quat = []
        cam_pos = []
        cam_quat = []
        
        for r in rows:
            ee_pos.append([float(r['ee_x']), float(r['ee_y']), float(r['ee_z'])])
            ee_quat.append([float(r['ee_qx']), float(r['ee_qy']), float(r['ee_qz']), float(r['ee_qw'])])
            cam_pos.append([float(r['cam_x']), float(r['cam_y']), float(r['cam_z'])])
            cam_quat.append([float(r['cam_qx']), float(r['cam_qy']), float(r['cam_qz']), float(r['cam_qw'])])
            
        ee_pos = np.array(ee_pos)
        cam_pos = np.array(cam_pos)
    except Exception as e:
        feedback.append(f"Data type error in CSV (non-numeric values): {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # CRITERION 3: Spatial Diversity (20 points)
    # Check if the robot actually moved through a significant volume
    std_pos = np.std(ee_pos, axis=0)
    total_std = np.sum(std_pos)
    
    if total_std > 0.05:
        score += 20
        feedback.append(f"Spatial diversity verified (stddev: {total_std:.3f}m) (+20)")
    else:
        feedback.append(f"Poses lack diversity. Robot barely moved (stddev: {total_std:.3f}m).")

    # CRITERION 4: Rigid Body Constraint (50 points)
    # The relative transformation M_{ee}^{cam} must be strictly constant
    T_rels = []
    try:
        for i in range(row_count):
            T_ee = pose_to_matrix(ee_pos[i], ee_quat[i])
            T_cam = pose_to_matrix(cam_pos[i], cam_quat[i])
            # T_rel = T_ee_inv * T_cam
            T_rel = matrix_inv(T_ee) @ T_cam
            T_rels.append(T_rel)
            
        T_rels = np.array(T_rels)
        
        # Calculate standard deviation of relative translations and rotations
        std_trans = np.std(T_rels[:, :3, 3], axis=0)
        std_rot = np.std(T_rels[:, :3, :3], axis=0)
        max_deviation = max(np.max(std_trans), np.max(std_rot))
        
        if max_deviation < 1e-3:
            score += 50
            feedback.append(f"Rigid body constraint passed perfectly (max dev: {max_deviation:.2e}) (+50)")
        else:
            feedback.append(f"Rigid body constraint FAILED (max dev: {max_deviation:.2e}). Data is inconsistent/faked.")
            
    except Exception as e:
        feedback.append(f"Mathematical validation error: {e}")

    # Cleanup temp files
    for tmp_file in [meta_tmp.name, csv_tmp.name, json_tmp.name]:
        try:
            os.unlink(tmp_file)
        except Exception:
            pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }