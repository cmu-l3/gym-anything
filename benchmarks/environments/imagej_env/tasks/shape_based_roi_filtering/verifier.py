#!/usr/bin/env python3
"""Verifier for shape_based_roi_filtering task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shape_based_roi_filtering(traj, env_info, task_info):
    """
    Verify the shape-based ROI filtering task.
    
    Scoring Criteria:
    1. Files Created (20 pts): Zip and CSV exist and are fresh.
    2. Shape Descriptors Used (20 pts): CSV has 'Circularity' column.
    3. Filtering Success (Lower Bound) (25 pts): Min circularity >= 0.84.
    4. Filtering Success (Upper Bound) (15 pts): Max circularity <= 1.0.
    5. Data Preservation (20 pts): ROI count is reasonable (>10) but filtered (<60).
    
    Pass threshold: 75 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/shape_roi_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Files Created (20 pts)
    if result.get("files_created_during_task"):
        score += 20
        feedback_parts.append("Files created successfully")
    else:
        feedback_parts.append("Files missing or old")

    # 2. Shape Descriptors Used (20 pts)
    if result.get("has_circularity_column"):
        score += 20
        feedback_parts.append("Circularity column found")
    else:
        feedback_parts.append("Circularity column missing in CSV")

    # 3. Filtering Success (Lower Bound) (25 pts)
    min_circ = result.get("min_circularity", 0.0)
    count = result.get("csv_row_count", 0)
    
    if count > 0:
        if min_circ >= 0.84:
            score += 25
            feedback_parts.append(f"Filtering valid (Min Circ: {min_circ:.3f})")
        else:
            feedback_parts.append(f"Filtering failed (Found particles with Circ: {min_circ:.3f} < 0.85)")
    else:
        feedback_parts.append("No measurements to verify filtering")

    # 4. Filtering Success (Upper Bound) (15 pts)
    max_circ = result.get("max_circularity", 0.0)
    if count > 0:
        if max_circ <= 1.01: # Tolerance for rounding
            score += 15
        else:
            feedback_parts.append(f"Invalid max circularity: {max_circ}")

    # 5. Data Preservation & Consistency (20 pts)
    zip_count = result.get("roi_count_in_zip", 0)
    csv_count = result.get("csv_row_count", 0)
    
    # Blobs image has ~60-70 blobs. We expect a subset.
    # If count is too low (e.g., < 5), they might have over-filtered or done nothing.
    # If count is too high (e.g., > 60), they didn't filter.
    
    count_ok = False
    if 10 <= csv_count <= 60:
        count_ok = True
    
    consistency_ok = False
    if abs(zip_count - csv_count) <= 2: # Allow small mismatch
        consistency_ok = True
        
    if count_ok and consistency_ok:
        score += 20
        feedback_parts.append(f"Counts valid (CSV: {csv_count}, Zip: {zip_count})")
    elif not count_ok:
        feedback_parts.append(f"Count suspicious ({csv_count}) - expected 10-60")
    elif not consistency_ok:
        feedback_parts.append(f"Mismatch between CSV rows ({csv_count}) and ROIs ({zip_count})")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }