#!/usr/bin/env python3
"""Verifier for work_item_triage_and_query task.

Scoring (100 points):
- At least 2 of 3 Priority 1 bugs now have an assignee: 30 pts
- At least 2 of 3 Priority 1 bugs have correct area path (Backend API): 25 pts
- Shared query named 'Critical Bug Backlog' exists: 30 pts
- At least 1 bug tagged with 'needs-owner': 15 pts

Pass threshold: 60 points
"""

import json
import logging
import os
import re
import tempfile

logger = logging.getLogger(__name__)


def verify_work_item_triage_and_query(traj, env_info, task_info):
    """Verify work item triage and query creation task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env(
                "C:/Users/Docker/task_results/work_item_triage_result.json",
                tmp.name,
            )
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}

        try:
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    p1_count = result.get("p1_bug_count", 0)
    assigned_count = result.get("p1_bugs_assigned_count", 0)
    correct_area_count = result.get("p1_bugs_correct_area_count", 0)
    tagged_count = result.get("p1_bugs_tagged_count", 0)
    query_found = result.get("critical_query_found", False)
    query_wiql = result.get("critical_query_wiql", "").lower()

    # -----------------------------------------------------------------------
    # GATE: If no P1 bugs were tracked in baseline, we can't verify
    # -----------------------------------------------------------------------
    if p1_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No Priority 1 bugs found in baseline — setup may have failed",
        }

    # -----------------------------------------------------------------------
    # Criterion 1: Priority 1 bugs assigned (30 pts)
    # -----------------------------------------------------------------------
    needed = max(2, p1_count - 1)  # Need at least 2 (or all if fewer than 3)
    if assigned_count >= p1_count:
        score += 30
        subscores["bugs_assigned"] = True
        feedback_parts.append(f"All {p1_count} Priority 1 bugs assigned")
    elif assigned_count >= needed:
        score += 20
        subscores["bugs_assigned"] = "partial"
        feedback_parts.append(f"{assigned_count}/{p1_count} Priority 1 bugs assigned")
    elif assigned_count >= 1:
        score += 10
        subscores["bugs_assigned"] = "minimal"
        feedback_parts.append(f"{assigned_count}/{p1_count} Priority 1 bugs assigned (need ≥{needed})")
    else:
        subscores["bugs_assigned"] = False
        feedback_parts.append("No Priority 1 bugs have been assigned")

    # -----------------------------------------------------------------------
    # Criterion 2: Priority 1 bugs in correct area path (25 pts)
    # -----------------------------------------------------------------------
    if correct_area_count >= p1_count:
        score += 25
        subscores["area_corrected"] = True
        feedback_parts.append(f"All {p1_count} Priority 1 bugs moved to Backend API area")
    elif correct_area_count >= needed:
        score += 15
        subscores["area_corrected"] = "partial"
        feedback_parts.append(f"{correct_area_count}/{p1_count} bugs in correct area (Backend API)")
    elif correct_area_count >= 1:
        score += 8
        subscores["area_corrected"] = "minimal"
        feedback_parts.append(f"{correct_area_count}/{p1_count} bugs in correct area (need ≥{needed})")
    else:
        subscores["area_corrected"] = False
        feedback_parts.append("No bugs moved to 'Backend API' area path")

    # -----------------------------------------------------------------------
    # Criterion 3: Shared query exists (30 pts)
    # -----------------------------------------------------------------------
    if query_found:
        score += 30
        subscores["query_created"] = True
        # Bonus: check if WIQL actually filters by P1 and Bug type
        wiql_valid = (
            "bug" in query_wiql
            and ("priority" in query_wiql or "1" in query_wiql)
        )
        if wiql_valid:
            feedback_parts.append("'Critical Bug Backlog' query found with valid WIQL (Bug + Priority filter)")
        else:
            feedback_parts.append("'Critical Bug Backlog' query found")
    else:
        subscores["query_created"] = False
        feedback_parts.append("No 'Critical Bug Backlog' shared query found")

    # -----------------------------------------------------------------------
    # Criterion 4: Tags added (15 pts)
    # -----------------------------------------------------------------------
    if tagged_count >= 1:
        score += 15
        subscores["tags_added"] = True
        feedback_parts.append(f"{tagged_count} bug(s) tagged with 'needs-owner'")
    else:
        subscores["tags_added"] = False
        feedback_parts.append("No bugs tagged with 'needs-owner'")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "details": {
            "p1_bug_count": p1_count,
            "assigned_count": assigned_count,
            "correct_area_count": correct_area_count,
            "tagged_count": tagged_count,
            "query_found": query_found,
        },
    }
