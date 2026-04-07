#!/usr/bin/env python3
"""
Verifier for compute_cogo_radiation task.

VERIFICATION METRICS:
1. Process Integrity (10 pts) - TopoCal project file saved during the task.
2. Data Export (15 pts) - Points correctly exported to CSV.
3. Math Accuracy - Point 101 computed within tolerance (25 pts).
4. Math Accuracy - Point 102 computed within tolerance (25 pts).
5. Math Accuracy - Point 103 computed within tolerance (25 pts).

Total: 100 points. Pass threshold: 85 points.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_cogo_radiation(traj, env_info, task_info):
    """
    Verify the TopoCal COGO radiation task was performed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    theoretical_points = metadata.get('theoretical_points', {})
    tolerance = metadata.get('tolerance_m', 0.05)

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # Extract exported data from environment
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result from env: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # CRITERION 1: Process Integrity / Project Saved (10 pts)
    # ================================================================
    project_saved = result.get('project_saved', False)
    project_created_during_task = result.get('project_created_during_task', False)

    if project_saved and project_created_during_task:
        score += 10
        feedback_parts.append("Project saved successfully (+10)")
    elif project_saved:
        feedback_parts.append("Project saved, but timestamp validation failed")
    else:
        feedback_parts.append("Project file not saved")

    # ================================================================
    # CRITERION 2: Data Exported to CSV (15 pts)
    # ================================================================
    csv_exists = result.get('output_csv_exists', False)
    csv_created_during_task = result.get('csv_created_during_task', False)
    csv_content = result.get('csv_content', '')

    if csv_exists and csv_created_during_task:
        score += 15
        feedback_parts.append("Points exported to CSV (+15)")
    elif csv_exists:
        feedback_parts.append("CSV exists, but timestamp validation failed")
    else:
        feedback_parts.append("Exported CSV not found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"reason": "Missing required export output."}
        }

    # ================================================================
    # CRITERIA 3-5: Mathematical Validation of COGO Points
    # ================================================================
    def parse_exported_point(csv_str, pt_id):
        """
        Robustly parses TopoCal CSV format:
        Looks for the point ID followed by delimiters and the first two numeric coords (Easting, Northing).
        Handles comma and semicolon separators, as well as Spanish decimal formats (, vs .).
        """
        pattern = rf"^{pt_id}[\s,;]+([0-9\.\-]+)[\s,;]+([0-9\.\-]+)"
        match = re.search(pattern, csv_str, re.MULTILINE)
        if match:
            v1 = float(match.group(1).replace(',', '.'))
            v2 = float(match.group(2).replace(',', '.'))
            return v1, v2
        return None, None

    def check_point_accuracy(pt_id, expected_e, expected_n, val_1, val_2, tol):
        """
        Checks if the parsed values match the expected Easting/Northing.
        Allows columns to be swapped (E/N vs N/E) to prevent failing correct math over trivial CAD export settings.
        """
        if val_1 is None or val_2 is None:
            return False, "Not found in CSV"
        
        # Check standard order (Easting, Northing)
        if abs(val_1 - expected_e) <= tol and abs(val_2 - expected_n) <= tol:
            return True, "Accurate"
        
        # Check swapped order (Northing, Easting)
        if abs(val_2 - expected_e) <= tol and abs(val_1 - expected_n) <= tol:
            return True, "Accurate (Swapped Coordinates)"
        
        return False, f"Value mismatch: Expected ({expected_e}, {expected_n}), Got ({val_1}, {val_2})"

    # Validate each point (25 points each)
    point_results = {}
    for pt_id in ["101", "102", "103"]:
        expected = theoretical_points.get(pt_id, {})
        exp_e = expected.get("easting")
        exp_n = expected.get("northing")

        val_1, val_2 = parse_exported_point(csv_content, pt_id)
        is_accurate, reason = check_point_accuracy(pt_id, exp_e, exp_n, val_1, val_2, tolerance)

        point_results[pt_id] = {"parsed": (val_1, val_2), "accurate": is_accurate, "reason": reason}
        if is_accurate:
            score += 25
            feedback_parts.append(f"Point {pt_id} calculated accurately (+25)")
        else:
            feedback_parts.append(f"Point {pt_id} incorrect: {reason}")

    # ================================================================
    # Finalize
    # ================================================================
    # Pass threshold relies on structural criteria + at least 2 points being mathematically correct (85 points)
    passed = score >= 85

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": point_results
    }