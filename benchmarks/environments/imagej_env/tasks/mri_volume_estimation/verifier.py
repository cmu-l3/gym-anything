#!/usr/bin/env python3
"""
Verifier for MRI Volume Estimation task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mri_volume_estimation(traj, env_info, task_info):
    """
    Verify the MRI volume estimation task.
    
    Criteria:
    1. Result file exists and was created during task (15 pts)
    2. Data completeness: >= 20 measurements (25 pts)
    3. Data reality: Area values vary across slices (std dev > 100) (20 pts)
       (Real brain slices vary greatly in size)
    4. Anatomical realism: Some large slices (>5000px) and some small (10 pts)
    5. Volume total reported or calculable (20 pts)
    6. Workflow evidence (10 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mri_volume_estimation_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Timestamp (15 pts)
    if result.get("file_exists", False):
        if result.get("file_created_after_start", False):
            score += 15
            feedback_parts.append("Result file created during task")
        else:
            score += 5
            feedback_parts.append("Result file exists but predates task start")
    else:
        feedback_parts.append("Result file not found")
        # Critical failure if file missing
        return {
            "passed": False,
            "score": 0,
            "feedback": "No result file found at ~/ImageJ_Data/results/mri_volume_results.csv (or alternatives)"
        }

    # Criterion 2: Data Completeness (25 pts)
    rows = result.get("total_data_rows", 0)
    if rows >= 50:
        score += 25
        feedback_parts.append(f"Excellent coverage ({rows} slices measured)")
    elif rows >= 20:
        score += 20
        feedback_parts.append(f"Good coverage ({rows} slices measured)")
    elif rows >= 10:
        score += 10
        feedback_parts.append(f"Partial coverage ({rows} slices measured)")
    else:
        feedback_parts.append(f"Insufficient measurements ({rows} rows, need 20+)")

    # Criterion 3: Data Variation (20 pts)
    # Real brain MRI slices vary significantly in tissue area
    std_dev = result.get("area_std_dev", 0)
    if std_dev > 500:
        score += 20
        feedback_parts.append(f"Data shows realistic anatomical variation (std dev {std_dev:.0f})")
    elif std_dev > 50:
        score += 10
        feedback_parts.append(f"Data shows minimal variation (std dev {std_dev:.0f})")
    else:
        feedback_parts.append("Data is constant or near-constant (suspicious for MRI stack)")

    # Criterion 4: Anatomical Realism (10 pts)
    # Should have some slices with significant tissue and some with little/none
    large_slices = result.get("areas_above_5000", 0)
    # Just checking if we captured the 'meaty' part of the brain
    if large_slices >= 5:
        score += 10
        feedback_parts.append("Found expected large brain slices")
    else:
        feedback_parts.append("Brain tissue areas seem too small (check thresholding)")

    # Criterion 5: Volume Total (20 pts)
    if result.get("has_volume_total", False):
        vol = result.get("volume_total_value", 0)
        score += 20
        feedback_parts.append(f"Total volume reported: {vol:.0f}")
    else:
        feedback_parts.append("Total volume not explicitly reported")

    # Criterion 6: Workflow/Effort (10 pts)
    # If we have substantial data, we assume workflow was followed
    if rows >= 20 and std_dev > 100:
        score += 10
        feedback_parts.append("Data indicates successful stack processing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }