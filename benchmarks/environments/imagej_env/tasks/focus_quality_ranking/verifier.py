#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_focus_quality_ranking(traj, env_info, task_info):
    """
    Verify the focus quality ranking task.
    
    Scoring Criteria:
    1. Result file exists and created during task (15 pts)
    2. Valid CSV structure with header (15 pts)
    3. Sufficient measurements (>=6 rows) (20 pts)
    4. StdDev column present and positive (20 pts)
    5. Mean column present (10 pts)
    6. Sorting (Descending StdDev) and Diversity (10 pts)
    7. Filename matching / Content validity (10 pts)
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File existence (15 pts)
    if result.get("file_exists", False):
        if result.get("created_after_start", False):
            score += 15
            feedback_parts.append("File created during task")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp issue")
    else:
        feedback_parts.append("Output file not found")
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. CSV Structure (15 pts)
    if result.get("has_header", False):
        score += 15
        feedback_parts.append("Valid CSV structure")
    else:
        feedback_parts.append("Invalid CSV structure or missing header")

    # 3. Measurement Count (20 pts)
    row_count = result.get("row_count", 0)
    if row_count >= 6:
        score += 20
        feedback_parts.append(f"Measured {row_count} images (>=6)")
    elif row_count > 0:
        score += int(20 * (row_count / 6))
        feedback_parts.append(f"Measured {row_count} images (partial)")
    else:
        feedback_parts.append("No measurements found")

    # 4. StdDev Column (20 pts)
    if result.get("has_stddev", False):
        if result.get("all_stddev_positive", False):
            score += 20
            feedback_parts.append("StdDev column valid")
        else:
            score += 10
            feedback_parts.append("StdDev column found but contains non-positive values")
    else:
        feedback_parts.append("StdDev column missing")

    # 5. Mean Column (10 pts)
    if result.get("has_mean", False):
        score += 10
        feedback_parts.append("Mean column found")
    else:
        feedback_parts.append("Mean column missing")

    # 6. Sorting & Diversity (10 pts)
    diversity = result.get("stddev_diversity", 0.0)
    is_sorted = result.get("is_sorted_desc", False)
    
    if diversity > 1.0: # Ensure values aren't all identical
        if is_sorted:
            score += 10
            feedback_parts.append("Correctly sorted by focus (descending StdDev)")
        else:
            score += 5
            feedback_parts.append("Data varies but not sorted by focus")
    else:
        feedback_parts.append("StdDev values lack diversity (potential fake data)")

    # 7. Filename Match (10 pts)
    matches = result.get("filenames_match", 0)
    if matches >= 3:
        score += 10
        feedback_parts.append(f"Matched {matches} filenames")
    elif matches > 0:
        score += 5
        feedback_parts.append(f"Matched {matches} filenames")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }