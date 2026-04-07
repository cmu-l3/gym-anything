#!/usr/bin/env python3
"""Verifier for snells_law_optics_lab task.

Checks that the agent:
1. Created calculate_n.py that reads the data and uses sine functions.
2. Created optics_report.odt (valid ODT).
3. Reported the average index of refraction (1.52).
4. Identified the material as Crown Glass.
"""

import json
import os
import tempfile


def verify_snells_law_optics_lab(traj, env_info, task_info):
    """Verify the optics lab calculation and report were completed correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/optics_analysis.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Check for parsing errors
    if result.get('error'):
        feedback.append(f"Note: {result['error']}")

    # Criterion 1: Python script exists and modified (10 pts)
    if result.get('script_exists'):
        if result.get('script_modified'):
            score += 10
            feedback.append("calculate_n.py saved successfully")
        else:
            score += 5
            feedback.append("calculate_n.py exists but mtime check failed")
    else:
        feedback.append("FAIL: calculate_n.py not found")

    # Criterion 2: Script uses math/sine functions (10 pts)
    if result.get('has_sin'):
        score += 10
        feedback.append("Script contains trigonometric math functions")
    elif result.get('script_exists'):
        feedback.append("Script missing 'sin' calculations")

    # Criterion 3: Script reads the file (10 pts)
    if result.get('has_csv'):
        score += 10
        feedback.append("Script contains file reading logic")
    elif result.get('script_exists'):
        feedback.append("Script missing file reading logic")

    # Criterion 4: Report exists and modified (20 pts)
    if result.get('report_exists'):
        if result.get('report_modified'):
            score += 20
            feedback.append("optics_report.odt saved successfully")
        else:
            score += 10
            feedback.append("optics_report.odt exists but mtime check failed")
    else:
        feedback.append("FAIL: optics_report.odt not found")

    # Criterion 5: Correct numerical calculation (30 pts)
    if result.get('has_1_52'):
        score += 30
        feedback.append("Report correctly states n = 1.52")
    elif result.get('has_1_51_or_53'):
        score += 15
        feedback.append("Report states n = 1.51 or 1.53 (rounding discrepancy - partial credit)")
    elif result.get('report_exists'):
        feedback.append("Report missing correct average index of refraction (1.52)")

    # Criterion 6: Material identified (20 pts)
    if result.get('has_glass'):
        score += 20
        feedback.append("Report correctly identifies material as Crown Glass")
    elif result.get('report_exists'):
        feedback.append("Report fails to identify 'Crown Glass'")

    # Pass threshold: 70 points
    # Must have both files and the correct numerical value or material to reach 70
    passed = score >= 70

    if passed:
        feedback.insert(0, "Lab workflow complete!")
    else:
        feedback.insert(0, f"FAILED: score {score} < 70")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "script_exists": result.get('script_exists', False),
            "script_logic": result.get('has_sin', False) and result.get('has_csv', False),
            "report_exists": result.get('report_exists', False),
            "correct_calculation": result.get('has_1_52', False),
            "correct_material": result.get('has_glass', False)
        }
    }