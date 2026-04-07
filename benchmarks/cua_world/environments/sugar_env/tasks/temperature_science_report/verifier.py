#!/usr/bin/env python3
"""Verifier for temperature_science_report task.

Checks that the agent created a science report in Sugar Write with:
- A data table containing temperature readings (22, 24, 21, 26, 23°C)
- An 'Analysis' section
- A 'Conclusion' section
Saved as temperature_report.odt in /home/ga/Documents/.
"""

import json
import os
import tempfile


def verify_temperature_science_report(traj, env_info, task_info):
    """Verify the temperature science report was created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/temperature_science_report_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: File exists and was modified during task (15 pts)
    if result.get('file_exists'):
        if result.get('file_modified'):
            score += 15
            feedback.append("temperature_report.odt saved")
        else:
            score += 5
            feedback.append("File exists but mtime check failed (may be pre-existing)")
    else:
        feedback.append("FAIL: temperature_report.odt not found in /home/ga/Documents/")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: File has meaningful content (5 pts)
    if result.get('file_size', 0) > 1000:
        score += 5
        feedback.append(f"File has content ({result['file_size']} bytes)")
    else:
        feedback.append(f"File small ({result.get('file_size', 0)} bytes)")

    # Criterion 3: Has a data table (15 pts)
    if result.get('has_table'):
        score += 15
        feedback.append("Data table present")
    else:
        feedback.append("No table found (temperature data should be in a table)")

    # Criterion 4: Temperature values in document (25 pts total)
    temp_pts = 0
    temp_feedback = []
    if result.get('has_temp_22'):
        temp_pts += 5
        temp_feedback.append("22°C")
    if result.get('has_temp_24'):
        temp_pts += 5
        temp_feedback.append("24°C")
    if result.get('has_temp_26'):
        temp_pts += 5
        temp_feedback.append("26°C")
    if result.get('has_all_temps'):
        temp_pts += 10
        temp_feedback.append("all 5 temps")

    score += temp_pts
    if temp_pts > 0:
        feedback.append(f"Temperature values found: {', '.join(temp_feedback)}")
    else:
        feedback.append("No temperature values (22,24,21,26,23) found in document")

    # Criterion 5: Has 'Analysis' section (20 pts)
    if result.get('has_analysis'):
        score += 20
        feedback.append("'Analysis' section found")
    else:
        feedback.append("Missing 'Analysis' section")

    # Criterion 6: Has 'Conclusion' section (20 pts)
    if result.get('has_conclusion'):
        score += 20
        feedback.append("'Conclusion' section found")
    else:
        feedback.append("Missing 'Conclusion' section")

    # Pass: score >= 65 AND both sections AND table AND file exists
    has_sections = result.get('has_analysis', False) and result.get('has_conclusion', False)
    passed = (score >= 65 and
              has_sections and
              result.get('has_table', False) and
              result.get('file_exists', False))

    if passed:
        feedback.append("Science report complete!")
    else:
        reasons = []
        if not result.get('has_analysis'):
            reasons.append("missing Analysis section")
        if not result.get('has_conclusion'):
            reasons.append("missing Conclusion section")
        if not result.get('has_table'):
            reasons.append("missing data table")
        if score < 65:
            reasons.append(f"score {score} < 65")
        feedback.append(f"FAILED: {'; '.join(reasons)}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "file_exists": result.get('file_exists', False),
            "has_table": result.get('has_table', False),
            "has_analysis": result.get('has_analysis', False),
            "has_conclusion": result.get('has_conclusion', False),
            "has_all_temps": result.get('has_all_temps', False)
        }
    }
