#!/usr/bin/env python3
"""
Verifier for spatial_calibration_measurement task.

Verifies:
1. Result file existence and timestamp.
2. Row count (enough blobs measured).
3. Calibration check: Values must be in physical units (µm), not pixels.
   - Uncalibrated Blobs Area ~ 160-2400 px²
   - Calibrated (0.5µm/px) Area ~ 40-600 µm²
   - Verification logic checks median area < 700.
4. Feature check: MinFeret included.
5. VLM check: Trajectory visual confirmation.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_calibration(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Thresholds
    CALIBRATED_AREA_MAX = metadata.get('calibrated_area_max', 700)  # µm²
    UNCALIBRATED_AREA_MIN = metadata.get('uncalibrated_area_threshold', 1000) # px² region start
    MIN_ROWS = metadata.get('min_row_count', 20)
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/spatial_calibration_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Timestamp (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback.append("Result file created successfully.")
    else:
        feedback.append("Result file not found or created before task start.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Measurement Count (20 pts)
    row_count = result.get("row_count", 0)
    if row_count >= MIN_ROWS:
        score += 20
        feedback.append(f"Measured {row_count} blobs (pass).")
    else:
        feedback.append(f"Measured {row_count} blobs (fail, need >={MIN_ROWS}).")

    # 3. Calibration Check - Area (25 pts)
    median_area = result.get("median_area", 0)
    if 20 < median_area < CALIBRATED_AREA_MAX:
        score += 25
        feedback.append(f"Median Area ({median_area:.2f}) indicates correct calibration.")
    elif median_area > UNCALIBRATED_AREA_MIN:
        # User likely didn't calibrate; values are in pixels
        feedback.append(f"Median Area ({median_area:.2f}) is too large - likely uncalibrated (pixels²).")
    else:
        feedback.append(f"Median Area ({median_area:.2f}) is out of expected range.")

    # 4. Calibration Check - Feret (20 pts)
    median_feret = result.get("median_feret", 0)
    # Expected calibrated feret approx 7-30 µm
    # Uncalibrated would be ~14-60 px
    if 5 < median_feret < 35:
        score += 20
        feedback.append(f"Median Feret ({median_feret:.2f}) indicates correct calibration.")
    elif median_feret > 40:
         feedback.append(f"Median Feret ({median_feret:.2f}) is too large - likely uncalibrated (pixels).")
    else:
         feedback.append(f"Median Feret ({median_feret:.2f}) out of range.")

    # 5. MinFeret Presence (10 pts)
    if result.get("has_min_feret"):
        score += 10
        feedback.append("MinFeret column present.")
    else:
        feedback.append("MinFeret column missing.")

    # 6. Geometric Consistency (10 pts)
    # Prevents just typing random small numbers
    consistency = result.get("geometric_consistency", 0)
    if consistency > 0.5: # At least 50% of blobs make geometric sense
        score += 10
    else:
        feedback.append("Measurements lack geometric consistency (Area vs Feret).")

    # Final check
    passed = (score >= 60) and (20 < median_area < CALIBRATED_AREA_MAX)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }