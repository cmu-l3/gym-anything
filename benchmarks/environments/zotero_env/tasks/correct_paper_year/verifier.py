#!/usr/bin/env python3
"""
Verifier for correct_paper_year task.

Task: Fix two deliberately corrupted publication years:
  - Einstein "On the Electrodynamics of Moving Bodies": 1906 -> 1905
  - Shannon "A Mathematical Theory of Communication":   1950 -> 1948

Scoring (100 points):
  - Einstein corrected to 1905:  50 pts
  - Shannon corrected to 1948:   50 pts

Pass threshold: 80 points (both papers fixed, or at least one plus partial)

Note: partial pass at 50 pts if exactly one paper is fixed.
Full pass requires both corrections.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_correct_paper_year(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/correct_paper_year_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Einstein corrected (50 pts)
    einstein_year = result.get("einstein_current_year")
    einstein_correct = result.get("einstein_correct", False)
    if einstein_correct:
        score += 50
        subscores["einstein_fixed"] = True
        feedback_parts.append(f"Einstein year corrected to {einstein_year}")
    else:
        subscores["einstein_fixed"] = False
        if einstein_year == "1906":
            feedback_parts.append("Einstein year still shows 1906 (should be 1905)")
        elif einstein_year:
            feedback_parts.append(f"Einstein year is {einstein_year} (expected 1905)")
        else:
            feedback_parts.append("Einstein paper not found in DB")

    # Criterion 2: Shannon corrected (50 pts)
    shannon_year = result.get("shannon_current_year")
    shannon_correct = result.get("shannon_correct", False)
    if shannon_correct:
        score += 50
        subscores["shannon_fixed"] = True
        feedback_parts.append(f"Shannon year corrected to {shannon_year}")
    else:
        subscores["shannon_fixed"] = False
        if shannon_year == "1950":
            feedback_parts.append("Shannon year still shows 1950 (should be 1948)")
        elif shannon_year:
            feedback_parts.append(f"Shannon year is {shannon_year} (expected 1948)")
        else:
            feedback_parts.append("Shannon paper not found in DB")

    passed = score >= 80  # both papers fixed = 100 pts; one fixed = 50 pts (fail)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
