#!/usr/bin/env python3
"""
Verifier for team_workload_rebalancing task.

Checks 6 independent criteria:
1. SSL cert WP reassigned from carol to bob (15pts)
2. SSL cert WP status changed to In progress (10pts)
3. Time logged on K8s WP (15pts)
4. New capacity planning WP created (20pts)
5. Comment added to blue-green WP (15pts)
6. Wiki page with workload review documentation (25pts)

Total: 100pts. Pass threshold: 65.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/workload_result.json"


def verify_team_workload_rebalancing(traj, env_info, task_info):
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

    # --- Anti-gaming gate ---
    ssl = result.get("ssl", {})
    capacity = result.get("capacity", {})
    if not ssl.get("found", False) and not capacity.get("found", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No SSL WP modifications or capacity WP found. Agent likely did nothing.",
        }

    # --- Criterion 1: SSL cert reassigned to bob (15pts) ---
    if ssl.get("found", False):
        assignee = (ssl.get("assignee") or "").lower()
        if "bob" in assignee:
            score += 15
            feedback.append("SSL cert WP reassigned to bob.smith.")
        elif assignee != "carol.williams":
            score += 5
            feedback.append(f"SSL cert WP reassigned to '{assignee}' (expected bob.smith).")
        else:
            feedback.append("SSL cert WP still assigned to carol.williams.")
    else:
        feedback.append("SSL cert WP not found.")

    # --- Criterion 2: SSL cert status to In progress (10pts) ---
    if ssl.get("found", False):
        ssl_status = (ssl.get("status") or "").lower()
        if ssl_status == "in progress":
            score += 10
            feedback.append("SSL cert WP status changed to 'In progress'.")
        elif ssl_status != "new":
            score += 5
            feedback.append(f"SSL cert WP status changed to '{ssl_status}' (expected 'In progress').")
        else:
            feedback.append("SSL cert WP status still 'New'.")

    # --- Criterion 3: Time logged on K8s WP (15pts) ---
    k8s = result.get("k8s", {})
    initial_time = result.get("initial_time_entries", 0)
    if k8s.get("found", False):
        te_count = k8s.get("time_entry_count", 0)
        if te_count > initial_time:
            score += 5
            feedback.append("Time entry created on K8s WP.")

            total_hours = float(k8s.get("total_hours", 0))
            if abs(total_hours - 1.5) < 0.1:
                score += 5
                feedback.append(f"Logged hours correct: {total_hours}h.")
            elif total_hours > 0:
                score += 2
                feedback.append(f"Logged hours {total_hours}h, expected 1.5h.")

            comments = k8s.get("comments", [])
            comment_text = " ".join(str(c).lower() for c in comments)
            if "workload" in comment_text or "reassessment" in comment_text:
                score += 5
                feedback.append("K8s time entry comment matches.")
            elif len(comment_text.strip()) > 5:
                score += 2
                feedback.append("K8s time entry has comment but doesn't match expected text.")
        else:
            feedback.append("No new time entries on K8s WP.")
    else:
        feedback.append("K8s WP not found.")

    # --- Criterion 4: Capacity planning WP created (20pts) ---
    if capacity.get("found", False):
        score += 6
        feedback.append("Capacity planning WP created.")

        c_type = (capacity.get("type_name") or "").lower()
        if c_type == "task":
            score += 4
            feedback.append("Capacity WP type is 'Task'.")
        else:
            feedback.append(f"Capacity WP type is '{c_type}', expected 'Task'.")

        c_assignee = (capacity.get("assignee") or "").lower()
        if "alice" in c_assignee:
            score += 4
            feedback.append("Capacity WP assigned to alice.johnson.")
        else:
            feedback.append(f"Capacity WP assigned to '{c_assignee}', expected 'alice.johnson'.")

        c_version = (capacity.get("version_name") or "").lower()
        if "sprint 2" in c_version or "deploy" in c_version:
            score += 3
            feedback.append("Capacity WP in Sprint 2 - Deploy Automation.")
        else:
            feedback.append(f"Capacity WP version is '{c_version}'.")

        c_desc = (capacity.get("description") or "").lower()
        if "velocity" in c_desc or "capacity" in c_desc or "workload" in c_desc:
            score += 3
            feedback.append("Capacity WP has relevant description.")
        elif len(c_desc) > 10:
            score += 1
            feedback.append("Capacity WP has description but missing key terms.")
    else:
        initial_count = result.get("initial_wp_count", 0)
        current_count = result.get("current_wp_count", 0)
        if current_count > initial_count:
            score += 3
            feedback.append("New WP created but with wrong subject.")
        else:
            feedback.append("Capacity planning WP NOT created.")

    # --- Criterion 5: Comment on blue-green WP (15pts) ---
    bluegreen = result.get("bluegreen", {})
    if bluegreen.get("found", False):
        notes = bluegreen.get("notes", [])
        all_notes = " ".join(str(n).lower() for n in notes)
        has_workload = "workload" in all_notes or "review" in all_notes
        has_priority = "priority" in all_notes or "top priority" in all_notes
        has_alice = "alice" in all_notes
        has_sprint = "sprint 2" in all_notes or "sprint" in all_notes

        matched = sum([has_workload, has_priority, has_alice, has_sprint])
        if matched >= 3:
            score += 15
            feedback.append("Comment on blue-green WP matches expected content.")
        elif matched >= 2:
            score += 10
            feedback.append("Partial comment on blue-green WP (some keywords missing).")
        elif matched >= 1:
            score += 5
            feedback.append("Comment on blue-green WP has some relevant content.")
        elif len(all_notes.strip()) > 10:
            score += 3
            feedback.append("Comment exists on blue-green WP but missing key terms.")
        else:
            feedback.append("No relevant comment found on blue-green WP.")
    else:
        feedback.append("Blue-green WP not found.")

    # --- Criterion 6: Wiki page with workload review (25pts) ---
    wiki = result.get("wiki", {})
    if wiki.get("exists", False):
        score += 7
        feedback.append("Wiki page 'Sprint Workload Review' exists.")

        content_length = wiki.get("content_length", 0)
        if content_length < 20:
            feedback.append("Wiki content too short.")
        else:
            wiki_score = 0
            if wiki.get("has_ssl", False):
                wiki_score += 4
                feedback.append("Wiki mentions SSL/certificate task.")
            if wiki.get("has_carol", False):
                wiki_score += 4
                feedback.append("Wiki mentions Carol.")
            if wiki.get("has_bob", False):
                wiki_score += 4
                feedback.append("Wiki mentions Bob.")
            if wiki.get("has_reassign", False):
                wiki_score += 3
                feedback.append("Wiki describes reassignment.")
            if wiki.get("has_overload", False):
                wiki_score += 3
                feedback.append("Wiki mentions overload/capacity reason.")

            if wiki_score == 0:
                feedback.append("Wiki content exists but missing all expected keywords.")
            score += wiki_score
    else:
        feedback.append("Wiki page 'Sprint Workload Review' NOT found.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
