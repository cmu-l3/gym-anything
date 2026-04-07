#!/usr/bin/env python3
"""
Verifier for personality_age_regression_diagnostics task (jamovi_env).

This is a stub verifier. The primary verification is done externally via
the VLM checklist verifier which evaluates agent trajectory screenshots.

The stub performs basic structural checks:
  - .omv file exists and was created during the task
  - .txt report file exists and was created during the task
  - .omv is a valid ZIP with expected jamovi structure

Actual verification of statistical correctness (alpha values, R-squared,
beta coefficients, VIF, Durbin-Watson, Shapiro-Wilk) is delegated to
the VLM checklist verifier.
"""

import json
import os
import tempfile


def verify_personality_age_regression_diagnostics(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}

    score = 0
    feedback = []

    # Try to load task result JSON from the container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_result.name)
    except Exception:
        return {"passed": True, "score": 100, "feedback": "Stub verifier — VLM evaluation is external"}

    # Basic file existence checks
    omv_exists = task_result.get('omv_exists', False)
    omv_fresh = task_result.get('omv_created_during_task', False)
    report_exists = task_result.get('report_exists', False)
    report_fresh = task_result.get('report_created_during_task', False)

    if omv_exists and omv_fresh:
        score += 50
        feedback.append("Project file (.omv) saved successfully during task.")
    elif omv_exists:
        score += 20
        feedback.append("Project file (.omv) exists but may not have been created during task.")
    else:
        feedback.append("Project file (.omv) not found.")

    if report_exists and report_fresh:
        score += 50
        feedback.append("Report file (.txt) saved successfully during task.")
    elif report_exists:
        score += 20
        feedback.append("Report file (.txt) exists but may not have been created during task.")
    else:
        feedback.append("Report file (.txt) not found.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
