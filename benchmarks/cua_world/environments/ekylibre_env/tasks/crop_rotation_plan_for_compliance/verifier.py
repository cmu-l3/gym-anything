#!/usr/bin/env python3
"""
Verifier for crop_rotation_plan_for_compliance task.

The agent must create >=3 new activity_productions for the 2024 growing season,
using >=2 distinct crop activity types, with land parcels assigned.

Scoring (100 points):
- 30 pts: >=3 new activity_productions created after task start
- 25 pts: Productions reference a 2024 campaign (campaign year = 2024)
- 25 pts: >=2 distinct activity types used across new productions
- 20 pts: Each new production has a valid land parcel (support_id) assigned

Pass threshold: 60 points
Mandatory: at least 1 new activity_production created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/crop_rotation_result.json"


def verify_crop_rotation_plan_for_compliance(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    new_count = int(result.get("new_productions_count", 0))
    distinct_acts = int(result.get("distinct_activities_count", 0))
    prods_2024 = int(result.get("productions_in_2024_campaign", 0))
    prods_with_support = int(result.get("productions_with_support", 0))
    new_productions = result.get("new_productions", [])

    # --- Mandatory check: at least 1 new production ---
    if new_count < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No new activity productions created — task not started",
        }

    # --- Criterion 1: >=3 new activity_productions (30 pts) ---
    if new_count >= 3:
        score += 30
        subscores["min_3_productions"] = True
        feedback_parts.append(f"Created {new_count} new activity productions (>=3 required)")
    elif new_count >= 2:
        score += 15
        subscores["min_3_productions"] = False
        feedback_parts.append(f"Created {new_count} new activity productions (2 of 3 required)")
    else:
        score += 5
        subscores["min_3_productions"] = False
        feedback_parts.append(f"Only {new_count} new activity production (need >=3)")

    # --- Criterion 2: Productions in 2024 campaign (25 pts) ---
    if prods_2024 >= 3:
        score += 25
        subscores["productions_in_2024"] = True
        feedback_parts.append(f"All {prods_2024} productions correctly placed in 2024 campaign")
    elif prods_2024 >= 1:
        score += 12
        subscores["productions_in_2024"] = False
        feedback_parts.append(f"{prods_2024}/{new_count} productions placed in 2024 campaign")
    else:
        subscores["productions_in_2024"] = False
        feedback_parts.append("No productions placed in a 2024 campaign")

    # --- Criterion 3: >=2 distinct activity types (25 pts) ---
    if distinct_acts >= 2:
        score += 25
        subscores["distinct_activities"] = True
        feedback_parts.append(f"{distinct_acts} distinct crop activity types used (rotation confirmed)")
    elif distinct_acts == 1:
        score += 5
        subscores["distinct_activities"] = False
        feedback_parts.append("Only 1 activity type used — no crop rotation diversity")
    else:
        subscores["distinct_activities"] = False
        feedback_parts.append("No distinct activities could be determined")

    # --- Criterion 4: Land parcels assigned (20 pts) ---
    if prods_with_support >= 3:
        score += 20
        subscores["parcels_assigned"] = True
        feedback_parts.append(f"{prods_with_support} productions have land parcels assigned")
    elif prods_with_support >= 1:
        score += 10
        subscores["parcels_assigned"] = False
        feedback_parts.append(f"Only {prods_with_support} productions have parcels assigned")
    else:
        subscores["parcels_assigned"] = False
        feedback_parts.append("No land parcels assigned to new productions")

    # Require 75+ so that productions+campaign alone (55 pts) do not pass;
    # crop rotation diversity (2+ activities) must be demonstrated.
    passed = score >= 75
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts) or "No subtasks completed",
        "subscores": subscores,
    }
