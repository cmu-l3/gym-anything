#!/usr/bin/env python3
"""
Verifier for sprint_release_planning task.

Checks 6 independent criteria via exported JSON from Rails queries:
1. Version "Sprint 4 - Payment Overhaul" exists with correct dates/status (15pts)
2. WP1 "Fix broken checkout on mobile Safari" moved to Sprint 4 (15pts)
3. WP2 "Add wishlist feature" moved to Sprint 4 (15pts)
4. WP1 status changed to "In progress" (15pts)
5. Time logged on WP1 (2h with comment) (20pts)
6. Wiki page "Sprint 4 Release Notes" exists with relevant content (20pts)

Total: 100pts. Pass threshold: 70.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/sprint_release_planning_result.json"


def verify_sprint_release_planning(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_FILE, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # --- Anti-gaming: do-nothing gate ---
    version_info = result.get("version", {})
    initial_version_count = result.get("initial_version_count", 0)
    current_version_count = result.get("current_version_count", 0)

    if not version_info.get("exists", False) and current_version_count <= initial_version_count:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No new version created. The agent likely did nothing.",
        }

    # --- Criterion 1: Version exists with correct properties (15pts) ---
    if version_info.get("exists", False):
        score += 5
        feedback.append("Version 'Sprint 4 - Payment Overhaul' exists.")

        v_status = (version_info.get("status") or "").lower()
        if v_status == "open":
            score += 3
            feedback.append("Version status is 'open'.")
        else:
            feedback.append(f"Version status is '{v_status}', expected 'open'.")

        v_start = version_info.get("start_date", "")
        v_due = version_info.get("due_date", "")
        if v_start == "2025-07-01":
            score += 3
            feedback.append("Version start date correct (2025-07-01).")
        else:
            feedback.append(f"Version start date '{v_start}', expected '2025-07-01'.")

        if v_due == "2025-07-31":
            score += 4
            feedback.append("Version due date correct (2025-07-31).")
        else:
            feedback.append(f"Version due date '{v_due}', expected '2025-07-31'.")
    else:
        feedback.append("Version 'Sprint 4 - Payment Overhaul' NOT found.")

    # --- Criterion 2: WP1 moved to Sprint 4 (15pts) ---
    wp1 = result.get("wp1", {})
    if wp1.get("found", False):
        wp1_version = (wp1.get("version_name") or "").strip()
        if wp1_version == "Sprint 4 - Payment Overhaul":
            score += 15
            feedback.append("WP1 'Fix broken checkout on mobile Safari' assigned to Sprint 4.")
        else:
            feedback.append(
                f"WP1 version is '{wp1_version}', expected 'Sprint 4 - Payment Overhaul'."
            )
    else:
        feedback.append("WP1 'Fix broken checkout on mobile Safari' not found in project.")

    # --- Criterion 3: WP2 moved to Sprint 4 (15pts) ---
    wp2 = result.get("wp2", {})
    if wp2.get("found", False):
        wp2_version = (wp2.get("version_name") or "").strip()
        if wp2_version == "Sprint 4 - Payment Overhaul":
            score += 15
            feedback.append("WP2 'Add wishlist feature' assigned to Sprint 4.")
        else:
            feedback.append(
                f"WP2 version is '{wp2_version}', expected 'Sprint 4 - Payment Overhaul'."
            )
    else:
        feedback.append("WP2 'Add wishlist feature' not found in project.")

    # --- Criterion 4: WP1 status changed to "In progress" (15pts) ---
    if wp1.get("found", False):
        wp1_status = (wp1.get("status") or "").strip().lower()
        if wp1_status == "in progress":
            score += 15
            feedback.append("WP1 status correctly changed to 'In progress'.")
        else:
            feedback.append(f"WP1 status is '{wp1_status}', expected 'in progress'.")

    # --- Criterion 5: Time logged on WP1 (20pts) ---
    time_data = result.get("time_entries", {})
    initial_time = result.get("initial_time_entries", 0)
    te_count = time_data.get("count", 0)

    if te_count > initial_time:
        score += 5
        feedback.append(f"Time entry created on WP1 ({te_count} entries).")

        total_hours = float(time_data.get("total_hours", 0))
        if abs(total_hours - 2.0) < 0.1:
            score += 8
            feedback.append(f"Logged hours correct: {total_hours}h.")
        elif total_hours > 0:
            score += 3
            feedback.append(f"Logged hours {total_hours}h, expected 2.0h.")
        else:
            feedback.append("Logged hours is 0.")

        comments = time_data.get("comments", [])
        comment_text = " ".join(str(c).lower() for c in comments)
        if "sprint planning" in comment_text or "initial investigation" in comment_text:
            score += 7
            feedback.append("Time entry comment matches expected text.")
        elif len(comment_text.strip()) > 0:
            score += 3
            feedback.append(f"Time entry has comment but doesn't match expected text.")
        else:
            feedback.append("Time entry comment is empty.")
    else:
        feedback.append("No new time entries found on WP1.")

    # --- Criterion 6: Wiki page exists with correct content (20pts) ---
    wiki = result.get("wiki", {})
    if wiki.get("exists", False):
        score += 6
        feedback.append(f"Wiki page 'Sprint 4 Release Notes' exists (length={wiki.get('content_length', 0)}).")

        content_length = wiki.get("content_length", 0)
        if content_length < 20:
            feedback.append("Wiki page content is too short (< 20 chars).")
        else:
            has_sprint = wiki.get("has_sprint_name", False)
            has_checkout = wiki.get("has_checkout_ref", False)
            has_wishlist = wiki.get("has_wishlist_ref", False)

            content_score = 0
            if has_sprint:
                content_score += 5
                feedback.append("Wiki mentions sprint name / Payment Overhaul.")
            else:
                feedback.append("Wiki missing sprint name reference.")

            if has_checkout:
                content_score += 5
                feedback.append("Wiki references checkout / Safari work package.")
            else:
                feedback.append("Wiki missing checkout/Safari reference.")

            if has_wishlist:
                content_score += 4
                feedback.append("Wiki references wishlist work package.")
            else:
                feedback.append("Wiki missing wishlist reference.")

            score += content_score
    else:
        feedback.append("Wiki page 'Sprint 4 Release Notes' NOT found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
