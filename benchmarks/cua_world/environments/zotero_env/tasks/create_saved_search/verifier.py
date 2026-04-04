#!/usr/bin/env python3
"""
Verifier for create_saved_search task.

Task: Create a saved search named 'Papers Since 2010' that finds papers
      published in 2010 or later.

Scoring (100 points):
  - Saved search named 'Papers Since 2010' exists:    40 pts
  - Search has at least one condition:                 20 pts
  - Condition involves date/year field:                20 pts
  - Condition uses a year threshold of 2009-2010:      20 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

TARGET_NAME = "Papers Since 2010"


def verify_create_saved_search(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/create_saved_search_result.json", tmp.name)
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

    all_searches = result.get("all_searches", [])

    # Criterion 1: Saved search exists with correct name (40 pts)
    search_found = result.get("search_found", False)
    actual_name = result.get("search_name", "")
    if search_found and actual_name == TARGET_NAME:
        score += 40
        subscores["correct_name"] = True
        feedback_parts.append(f"Saved search '{TARGET_NAME}' found")
    elif search_found:
        # Found a search but name differs slightly — partial credit
        score += 25
        subscores["correct_name"] = "partial"
        feedback_parts.append(f"Saved search found with name '{actual_name}' (expected '{TARGET_NAME}')")
    else:
        subscores["correct_name"] = False
        search_names = [s["name"] for s in all_searches]
        feedback_parts.append(
            f"No saved search named '{TARGET_NAME}' found. Existing searches: {search_names}"
        )
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    # Criterion 2: Has at least one condition (20 pts)
    condition_count = result.get("condition_count", 0)
    if condition_count >= 1:
        score += 20
        subscores["has_conditions"] = True
        feedback_parts.append(f"Search has {condition_count} condition(s)")
    else:
        subscores["has_conditions"] = False
        feedback_parts.append("Search has no conditions configured")

    # Criterion 3: Condition involves date/year field (20 pts)
    if result.get("has_date_condition"):
        score += 20
        subscores["date_condition"] = True
        conditions = result.get("conditions", [])
        cond_summary = [f"{c['condition']} {c['operator']} {c['value']}" for c in conditions[:3]]
        feedback_parts.append(f"Date/year condition found: {cond_summary}")
    else:
        subscores["date_condition"] = False
        conditions = result.get("conditions", [])
        cond_summary = [f"{c['condition']} {c['operator']} {c['value']}" for c in conditions[:3]]
        feedback_parts.append(f"No date/year condition. Conditions: {cond_summary}")

    # Criterion 4: Year threshold of 2009-2010 (20 pts)
    if result.get("has_year_threshold"):
        score += 20
        subscores["year_threshold"] = True
        threshold = result.get("year_threshold_value")
        feedback_parts.append(f"Year threshold correctly set (value: {threshold})")
    else:
        subscores["year_threshold"] = False
        threshold = result.get("year_threshold_value")
        if threshold:
            feedback_parts.append(f"Year threshold found ({threshold}) but not in expected range 2009-2015")
        else:
            feedback_parts.append("Could not extract year threshold from condition value")

    passed = score >= 70 and search_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
