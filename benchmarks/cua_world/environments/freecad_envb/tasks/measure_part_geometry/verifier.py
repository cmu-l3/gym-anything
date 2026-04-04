#!/usr/bin/env python3
"""
Verifier for measure_part_geometry task.

Checks:
1. Report file exists and was created during the task.
2. Report file format is correct.
3. Values match the ground truth (calculated inside the container) within tolerance.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_part_geometry(traj, env_info, task_info):
    """
    Verify the geometry measurement report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Check 1: File Existence & Anti-Gaming (10 pts) ---
    if not result.get("report_exists", False):
        return {"passed": False, "score": 0, "feedback": "Measurement report file not found."}
    
    if not result.get("report_created_during_task", False):
        feedback_parts.append("Warning: Report file timestamp indicates it wasn't created during this session.")
        # We allow it but deduct points if it looks like they used an old file
        score += 5
    else:
        score += 10
        feedback_parts.append("Report file created successfully.")

    # --- Load Ground Truth ---
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env(result.get("ground_truth_path", "/tmp/ground_truth.json"), gt_file.name)
        with open(gt_file.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load ground truth: {e}")
        return {"passed": False, "score": score, "feedback": "System error: could not load ground truth data."}
    finally:
        if os.path.exists(gt_file.name):
            os.unlink(gt_file.name)

    if not ground_truth.get("success", False):
        return {"passed": False, "score": score, "feedback": f"System error: Ground truth generation failed ({ground_truth.get('error')})"}

    # --- Load User Report ---
    report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    user_data = {}
    try:
        copy_from_env(result.get("report_file_path"), report_file.name)
        with open(report_file.name, 'r') as f:
            lines = f.readlines()
            for line in lines:
                if ":" in line:
                    key, val = line.split(":", 1)
                    try:
                        user_data[key.strip()] = float(val.strip())
                    except ValueError:
                        pass
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read report file: {e}"}
    finally:
        if os.path.exists(report_file.name):
            os.unlink(report_file.name)

    # --- Compare Values ---
    # Tolerances
    TOL_PCT = 0.05  # 5%
    TOL_ABS = 2.0   # 2mm for CoM

    required_fields = [
        "BoundingBox_X", "BoundingBox_Y", "BoundingBox_Z",
        "Volume", "SurfaceArea",
        "CenterOfMass_X", "CenterOfMass_Y", "CenterOfMass_Z"
    ]

    # Check format (10 pts)
    format_valid = all(k in user_data for k in required_fields)
    if format_valid:
        score += 10
        feedback_parts.append("Report format correct.")
    else:
        missing = [k for k in required_fields if k not in user_data]
        feedback_parts.append(f"Missing fields: {', '.join(missing)}")

    # Check Geometry (80 pts distributed)
    
    # Bounding Box (30 pts)
    bbox_score = 0
    for axis in ["X", "Y", "Z"]:
        key = f"BoundingBox_{axis}"
        gt_val = ground_truth.get(key, 0)
        user_val = user_data.get(key, 0)
        
        if gt_val > 0 and abs(user_val - gt_val) / gt_val <= TOL_PCT:
            bbox_score += 10
    score += bbox_score
    if bbox_score < 30:
        feedback_parts.append(f"Bounding box accuracy: {bbox_score}/30")

    # Volume (20 pts)
    gt_vol = ground_truth.get("Volume", 0)
    user_vol = user_data.get("Volume", 0)
    if gt_vol > 0 and abs(user_vol - gt_vol) / gt_vol <= TOL_PCT:
        score += 20
    else:
        feedback_parts.append("Volume incorrect.")

    # Surface Area (10 pts)
    gt_area = ground_truth.get("SurfaceArea", 0)
    user_area = user_data.get("SurfaceArea", 0)
    if gt_area > 0 and abs(user_area - gt_area) / gt_area <= TOL_PCT:
        score += 10
    else:
        feedback_parts.append("Surface area incorrect.")

    # Center of Mass (20 pts)
    # All 3 must be close to get points
    com_correct = True
    for axis in ["X", "Y", "Z"]:
        key = f"CenterOfMass_{axis}"
        gt_val = ground_truth.get(key, 0)
        user_val = user_data.get(key, 0)
        if abs(user_val - gt_val) > TOL_ABS:
            com_correct = False
            break
    
    if com_correct:
        score += 20
    else:
        feedback_parts.append("Center of Mass incorrect.")

    # --- Final Verdict ---
    passed = score >= 60 and bbox_score >= 20 and user_vol > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }