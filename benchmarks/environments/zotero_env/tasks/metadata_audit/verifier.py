#!/usr/bin/env python3
"""
Verifier for metadata_audit task.

Task: Audit 25 biology/medicine papers and fix all metadata errors:
  - 5 papers have wrong years (stored 10 years off from correct)
  - 5 papers have swapped first/last author names
  - 5 papers have placeholder abstracts ("Abstract not available")

Scoring (100 points):
  - Year errors fixed (5 papers): 40 pts (8 each)
  - Name swap errors fixed (5 papers): 35 pts (7 each)
  - Abstract placeholders fixed (5 papers): 25 pts (5 each)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_metadata_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/metadata_audit_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Year errors fixed (40 pts, 8 each)
    year_data = result.get("year_errors", {})
    year_fixed_count = 0
    year_correct_count = 0
    for title, info in year_data.items():
        if info.get("fixed"):
            year_fixed_count += 1
        if info.get("correct"):
            year_correct_count += 1

    year_pts = year_fixed_count * 8
    score += year_pts
    subscores["year_errors_fixed"] = f"{year_fixed_count}/5"
    subscores["year_errors_correct"] = f"{year_correct_count}/5"
    if year_fixed_count == 5:
        feedback_parts.append(f"All 5 year errors fixed ({year_correct_count}/5 exactly correct)")
    else:
        feedback_parts.append(f"Year errors fixed: {year_fixed_count}/5")

    # Criterion 2: Name swap errors fixed (35 pts, 7 each)
    name_data = result.get("name_errors", {})
    name_fixed_count = 0
    name_correct_count = 0
    for title, info in name_data.items():
        if info.get("fixed"):
            name_fixed_count += 1
        if info.get("correct"):
            name_correct_count += 1

    name_pts = name_fixed_count * 7
    score += name_pts
    subscores["name_errors_fixed"] = f"{name_fixed_count}/5"
    subscores["name_errors_correct"] = f"{name_correct_count}/5"
    if name_fixed_count == 5:
        feedback_parts.append(f"All 5 author name errors fixed ({name_correct_count}/5 exactly correct)")
    else:
        feedback_parts.append(f"Author name errors fixed: {name_fixed_count}/5")

    # Criterion 3: Abstract placeholders fixed (25 pts, 5 each)
    abstract_data = result.get("abstract_placeholders", {})
    abstract_fixed_count = sum(1 for info in abstract_data.values() if info.get("fixed"))

    abstract_pts = abstract_fixed_count * 5
    score += abstract_pts
    subscores["abstract_placeholders_fixed"] = f"{abstract_fixed_count}/5"
    if abstract_fixed_count == 5:
        feedback_parts.append("All 5 placeholder abstracts fixed")
    else:
        feedback_parts.append(f"Placeholder abstracts fixed: {abstract_fixed_count}/5")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
