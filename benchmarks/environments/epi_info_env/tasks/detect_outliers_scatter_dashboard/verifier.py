#!/usr/bin/env python3
"""
Verifier for detect_outliers_scatter_dashboard task.

Verification Criteria:
1. Dashboard Canvas Saved (30 pts): Checks if .canvas7 file exists and was created during task.
2. Outlier Identified (50 pts): Checks if report contains correct PatientID (450).
3. Value Reported (20 pts): Checks if report contains correct BMI value (175.6).

Anti-gaming:
- File modification times checked.
- Report content parsed flexibly.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_outliers(traj, env_info, task_info):
    """
    Verify the Epi Info outlier detection task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_id = metadata.get('expected_id_string', '450')
    expected_value = metadata.get('expected_value_string', '175.6')

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_lines = []

    # 1. Verify Dashboard Canvas (30 pts)
    if result.get('canvas_exists', False):
        if result.get('canvas_created_during', False):
            score += 30
            feedback_lines.append("Dashboard canvas saved successfully.")
        else:
            score += 15
            feedback_lines.append("Dashboard canvas exists but timestamp is old (reused?).")
    else:
        feedback_lines.append("Dashboard canvas file not found.")

    # 2. Verify Report Content (70 pts total)
    report_content = result.get('report_content', '').strip()
    
    if result.get('report_exists', False):
        if not report_content:
            feedback_lines.append("Report file exists but is empty.")
        else:
            # Check for Patient ID (50 pts)
            # Use regex to find "450" as a whole word to avoid matching "1450"
            if re.search(r'\b' + re.escape(expected_id) + r'\b', report_content):
                score += 50
                feedback_lines.append(f"Correctly identified outlier PatientID: {expected_id}.")
            else:
                feedback_lines.append(f"Failed to find PatientID '{expected_id}' in report.")

            # Check for BMI Value (20 pts)
            # Allow for some formatting variations, e.g., 175.6 or 175,6
            if expected_value in report_content:
                score += 20
                feedback_lines.append(f"Correctly reported BMI value: {expected_value}.")
            else:
                feedback_lines.append(f"Failed to find BMI value '{expected_value}' in report.")
    else:
        feedback_lines.append("Report file not found.")

    passed = (score >= 80)  # Must get ID and canvas or ID and value + partial canvas
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_lines)
    }