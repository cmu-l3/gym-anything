#!/usr/bin/env python3
"""Verifier for sprint_health_audit task.

Scoring (100 points):
- Team capacity configured in Sprint 1 (>=1 member, >=1 hr/day): 20 pts
- At least 2 work items moved out of Sprint 1: 40 pts (20 per item, cap 2)
- Sprint 1 story points reduced by >=35% from initial 37: 20 pts
- At least 1 moved item has a comment explaining deferral: 20 pts

Pass threshold: 60 points

Wrong-target guard: If export JSON is missing/corrupt, fail with score=0.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

INITIAL_STORY_POINTS = 37
REDUCTION_THRESHOLD = 0.35  # 35% reduction required
MIN_ITEMS_MOVED = 2


def verify_sprint_health_audit(traj, env_info, task_info):
    """Verify sprint health audit task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env("C:/Users/Docker/task_results/sprint_health_audit_result.json", tmp.name)
        except Exception as e:
            logger.warning(f"Primary path failed: {e}, trying fallback")
            try:
                copy_from_env(r"C:\Users\Docker\task_results\sprint_health_audit_result.json", tmp.name)
            except Exception as e2:
                return {"passed": False, "score": 0, "feedback": f"Result file not found: {e2}"}

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

    # -----------------------------------------------------------------------
    # Criterion 1: Team capacity configured (20 pts)
    # -----------------------------------------------------------------------
    capacity_set = result.get("team_capacity_set", False)
    capacity_details = result.get("capacity_details", [])
    if capacity_set:
        score += 20
        subscores["capacity_configured"] = True
        feedback_parts.append("Team capacity configured in Sprint 1")
    else:
        subscores["capacity_configured"] = False
        feedback_parts.append("Team capacity not configured in Sprint 1")

    # -----------------------------------------------------------------------
    # Criterion 2: Items moved out of Sprint 1 (20 pts per item, up to 40 pts)
    # -----------------------------------------------------------------------
    items_moved = result.get("items_moved_out_of_sprint1", 0)
    if items_moved >= MIN_ITEMS_MOVED:
        pts = min(40, items_moved * 20)
        score += pts
        subscores["items_moved"] = items_moved
        feedback_parts.append(f"{items_moved} work item(s) moved out of Sprint 1 (+{pts} pts)")
    elif items_moved == 1:
        score += 20
        subscores["items_moved"] = 1
        feedback_parts.append("1 work item moved out of Sprint 1 (need >=2 for full credit)")
    else:
        subscores["items_moved"] = 0
        feedback_parts.append("No work items moved out of Sprint 1")

    # -----------------------------------------------------------------------
    # Criterion 3: Sprint 1 story points reduced >=35% (20 pts)
    # -----------------------------------------------------------------------
    baseline_pts = result.get("baseline_story_points", INITIAL_STORY_POINTS)
    sprint1_pts_after = result.get("sprint1_story_points_after", baseline_pts)
    if baseline_pts > 0:
        reduction = (baseline_pts - sprint1_pts_after) / baseline_pts
    else:
        reduction = 0.0

    if reduction >= REDUCTION_THRESHOLD:
        score += 20
        subscores["points_reduced"] = True
        feedback_parts.append(
            f"Sprint 1 story points reduced from {baseline_pts} to {sprint1_pts_after} "
            f"({reduction:.0%} reduction)"
        )
    else:
        subscores["points_reduced"] = False
        feedback_parts.append(
            f"Sprint 1 story points: {sprint1_pts_after} (was {baseline_pts}, "
            f"need ≥35% reduction, got {reduction:.0%})"
        )

    # -----------------------------------------------------------------------
    # Criterion 4: At least 1 moved item has a comment (20 pts)
    # -----------------------------------------------------------------------
    items_with_comments = result.get("items_with_comments", 0)
    if items_with_comments >= 1:
        score += 20
        subscores["comments_added"] = True
        feedback_parts.append(f"Comments found on {items_with_comments} moved work item(s)")
    else:
        subscores["comments_added"] = False
        feedback_parts.append("No comments found on moved work items")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "details": {
            "items_moved": items_moved,
            "sprint1_points_after": sprint1_pts_after,
            "baseline_points": baseline_pts,
            "team_capacity_set": capacity_set,
            "items_with_comments": items_with_comments,
        },
    }
