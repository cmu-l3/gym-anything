#!/usr/bin/env python3
"""Verifier for sugar_activity_cloning task.

Checks that:
1. MathTools.activity directory was created
2. activity.info was updated with correct name, bundle_id, icon, and summary
3. Icon SVG file was successfully renamed to math-tools.svg
4. A report file was generated containing the original and new bundle IDs
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sugar_activity_cloning(traj, env_info, task_info):
    """Verify the activity clone and reconfiguration."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Math Tools')
    expected_bundle_id = metadata.get('expected_bundle_id', 'org.laptop.MathTools')
    expected_icon_prop = metadata.get('expected_icon_prop', 'math-tools')
    expected_summary = metadata.get('expected_summary', 'A dedicated calculator for math class.')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/sugar_activity_cloning_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Track essential criteria
    key_criteria = {
        "dir": False,
        "name": False,
        "bundle": False
    }

    # Anti-gaming: Ensure files were modified during the task
    if not (result.get('info_modified_during_task') or result.get('report_modified_during_task')):
        logger.warning("Files do not appear to be modified during the task (failed anti-gaming check)")

    # 1. Directory exists (10 pts)
    if result.get('dir_exists'):
        score += 10
        key_criteria["dir"] = True
        feedback.append("MathTools.activity directory exists")
    else:
        feedback.append("MathTools.activity directory NOT found")

    # 2. activity.info exists (10 pts)
    if result.get('info_exists'):
        score += 10
        feedback.append("activity.info found")
    else:
        feedback.append("activity.info NOT found")

    # Parse INI data
    info_data = result.get('info_data', {})
    
    # 3. Correct Name (15 pts)
    actual_name = info_data.get('name', '')
    if actual_name == expected_name:
        score += 15
        key_criteria["name"] = True
        feedback.append(f"Name correctly set to '{expected_name}'")
    elif actual_name.lower() == expected_name.lower():
        score += 5  # partial for case mismatch
        feedback.append(f"Name set but wrong case: '{actual_name}'")
    else:
        feedback.append(f"Name incorrect: expected '{expected_name}', got '{actual_name}'")

    # 4. Correct Bundle ID (15 pts)
    actual_bundle = info_data.get('bundle_id', '')
    if actual_bundle == expected_bundle_id:
        score += 15
        key_criteria["bundle"] = True
        feedback.append(f"Bundle ID correctly set to '{expected_bundle_id}'")
    else:
        feedback.append(f"Bundle ID incorrect: expected '{expected_bundle_id}', got '{actual_bundle}'")

    # 5. Correct Icon Property (10 pts)
    actual_icon = info_data.get('icon', '')
    if actual_icon == expected_icon_prop:
        score += 10
        feedback.append(f"Icon property correctly set to '{expected_icon_prop}'")
    else:
        feedback.append(f"Icon property incorrect: expected '{expected_icon_prop}', got '{actual_icon}'")

    # 6. Correct Summary (10 pts)
    actual_summary = info_data.get('summary', '')
    if actual_summary == expected_summary:
        score += 10
        feedback.append("Summary correctly set")
    elif actual_summary and expected_summary.lower() in actual_summary.lower():
        score += 5
        feedback.append("Summary partially correct")
    else:
        feedback.append(f"Summary incorrect: got '{actual_summary}'")

    # 7. Icon File Renamed (15 pts)
    if result.get('svg_exists'):
        score += 15
        feedback.append("SVG icon successfully renamed to math-tools.svg")
    else:
        feedback.append("math-tools.svg NOT found in the activity folder")

    # 8. Report File Accurate (15 pts)
    original_id = result.get('original_bundle_id', 'org.laptop.Calculate')
    if result.get('report_exists'):
        lines = result.get('report_lines', [])
        report_score = 0
        if len(lines) >= 2:
            if lines[0] == original_id:
                report_score += 7
            if lines[1] == expected_bundle_id:
                report_score += 8
        
        if report_score == 15:
            score += 15
            feedback.append("Report file is correct")
        elif report_score > 0:
            score += report_score
            feedback.append("Report file is partially correct")
        else:
            feedback.append("Report file contains incorrect values")
    else:
        feedback.append("activity_clone_report.txt NOT found")

    # Final pass logic
    is_passed = (score >= 70) and all(key_criteria.values())

    if is_passed:
        feedback.insert(0, "SUCCESS: Activity successfully cloned and configured.")
    else:
        feedback.insert(0, f"FAILED: Score {score}/100 or missing key criteria (Dir: {key_criteria['dir']}, Name: {key_criteria['name']}, Bundle: {key_criteria['bundle']}).")

    return {
        "passed": is_passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }