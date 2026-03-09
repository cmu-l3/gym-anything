#!/usr/bin/env python3
"""
Verifier for project_retrospective_documentation task.

Checks 6 independent criteria:
1. DB optimization WP closed with verification comment (15pts)
2. Search WP carry-over comment added (12pts)
3. Time logged on search WP (13pts)
4. New version 'Sprint 2 - Performance & Search' created (15pts)
5. Search WP moved to new version (15pts)
6. Wiki retrospective page with structured content (30pts)

Total: 100pts. Pass threshold: 65.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/retro_result.json"


def verify_project_retrospective_documentation(traj, env_info, task_info):
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
    version_info = result.get("version", {})
    wiki = result.get("wiki", {})
    initial_version_count = result.get("initial_version_count", 0)
    current_version_count = result.get("current_version_count", 0)

    if not version_info.get("exists", False) and not wiki.get("exists", False) \
            and current_version_count <= initial_version_count:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No version created and no wiki page found. Agent likely did nothing.",
        }

    # --- Criterion 1: DB optimization WP closed with comment (15pts) ---
    db = result.get("db_optimize", {})
    if db.get("found", False):
        db_status = (db.get("status") or "").lower()
        if db_status in ("closed", "resolved"):
            score += 5
            feedback.append(f"DB optimization WP status is '{db_status}'.")
        else:
            feedback.append(f"DB optimization WP status is '{db_status}', expected 'Closed'.")

        db_notes = db.get("notes", [])
        db_all_notes = " ".join(str(n).lower() for n in db_notes)
        has_verified = "verified" in db_all_notes or "production" in db_all_notes
        has_n1 = "n+1" in db_all_notes or "n1" in db_all_notes or "queries" in db_all_notes
        has_perf = "load" in db_all_notes or "0.4" in db_all_notes or "reduced" in db_all_notes

        matched = sum([has_verified, has_n1, has_perf])
        if matched >= 2:
            score += 10
            feedback.append("DB optimization WP has verification comment with performance data.")
        elif matched >= 1:
            score += 5
            feedback.append("DB optimization WP has partial verification comment.")
        elif len(db_all_notes.strip()) > 10:
            score += 3
            feedback.append("DB optimization WP has comment but missing verification keywords.")
        else:
            feedback.append("No verification comment on DB optimization WP.")
    else:
        feedback.append("DB optimization WP not found.")

    # --- Criterion 2: Search WP carry-over comment (12pts) ---
    search = result.get("search", {})
    if search.get("found", False):
        s_notes = search.get("notes", [])
        s_all_notes = " ".join(str(n).lower() for n in s_notes)
        has_carry = "carry" in s_all_notes or "carrying over" in s_all_notes
        has_sprint2 = "sprint 2" in s_all_notes
        has_percent = "70%" in s_all_notes or "70 %" in s_all_notes or "percent" in s_all_notes
        has_faceted = "facet" in s_all_notes or "filter" in s_all_notes

        matched = sum([has_carry, has_sprint2, has_percent, has_faceted])
        if matched >= 3:
            score += 12
            feedback.append("Search WP carry-over comment matches expected content.")
        elif matched >= 2:
            score += 8
            feedback.append("Search WP has good carry-over comment (some details missing).")
        elif matched >= 1:
            score += 4
            feedback.append("Search WP has partial carry-over comment.")
        elif len(s_all_notes.strip()) > 10:
            score += 2
            feedback.append("Search WP has comment but missing carry-over keywords.")
        else:
            feedback.append("No carry-over comment on search WP.")
    else:
        feedback.append("Search WP not found.")

    # --- Criterion 3: Time logged on search WP (13pts) ---
    if search.get("found", False):
        initial_time = result.get("initial_time_entries", 0)
        te_count = search.get("time_entry_count", 0)
        if te_count > initial_time:
            score += 4
            feedback.append("Time entry created on search WP.")

            total_hours = float(search.get("total_hours", 0))
            if abs(total_hours - 4.0) < 0.1:
                score += 5
                feedback.append(f"Logged hours correct: {total_hours}h.")
            elif total_hours > 0:
                score += 2
                feedback.append(f"Logged hours {total_hours}h, expected 4.0h.")

            t_comments = search.get("time_comments", [])
            t_text = " ".join(str(c).lower() for c in t_comments)
            if "retrospective" in t_text or "code review" in t_text or "documentation" in t_text:
                score += 4
                feedback.append("Time entry comment matches.")
            elif len(t_text.strip()) > 5:
                score += 2
                feedback.append("Time entry has comment but doesn't match expected text.")
        else:
            feedback.append("No new time entries on search WP.")

    # --- Criterion 4: New version created (15pts) ---
    if version_info.get("exists", False):
        score += 5
        feedback.append("Version 'Sprint 2 - Performance & Search' exists.")

        v_status = (version_info.get("status") or "").lower()
        if v_status == "open":
            score += 3
            feedback.append("Version status is 'open'.")
        else:
            feedback.append(f"Version status is '{v_status}', expected 'open'.")

        v_start = version_info.get("start_date", "")
        v_due = version_info.get("due_date", "")
        if v_start == "2025-08-01":
            score += 3
            feedback.append("Version start date correct.")
        else:
            feedback.append(f"Version start date '{v_start}', expected '2025-08-01'.")

        if v_due == "2025-08-31":
            score += 4
            feedback.append("Version due date correct.")
        else:
            feedback.append(f"Version due date '{v_due}', expected '2025-08-31'.")
    else:
        feedback.append("Version 'Sprint 2 - Performance & Search' NOT found.")

    # --- Criterion 5: Search WP moved to new version (15pts) ---
    if search.get("found", False):
        s_version = (search.get("version_name") or "").strip()
        if s_version == "Sprint 2 - Performance & Search":
            score += 15
            feedback.append("Search WP moved to 'Sprint 2 - Performance & Search'.")
        elif "sprint 2" in s_version.lower() and "performance" in s_version.lower():
            score += 12
            feedback.append(f"Search WP moved to '{s_version}' (close match).")
        elif s_version != "Sprint 1 - Launch MVP":
            score += 5
            feedback.append(f"Search WP moved to '{s_version}' (expected Sprint 2 - Performance & Search).")
        else:
            feedback.append("Search WP still in Sprint 1.")

    # --- Criterion 6: Wiki retrospective page (30pts) ---
    if wiki.get("exists", False):
        score += 8
        feedback.append("Wiki page 'Sprint 1 Retrospective' exists.")

        content_length = wiki.get("content_length", 0)
        if content_length < 30:
            feedback.append("Wiki content too short.")
        else:
            wiki_score = 0
            if wiki.get("has_went_well", False):
                wiki_score += 4
                feedback.append("Wiki has 'what went well' section.")
            if wiki.get("has_didnt_go_well", False):
                wiki_score += 4
                feedback.append("Wiki has 'what didn't go well' section.")
            if wiki.get("has_database", False):
                wiki_score += 4
                feedback.append("Wiki mentions database optimization.")
            if wiki.get("has_search", False):
                wiki_score += 4
                feedback.append("Wiki mentions search/Elasticsearch.")
            if wiki.get("has_estimation", False):
                wiki_score += 3
                feedback.append("Wiki discusses estimation/velocity.")
            if wiki.get("has_action_items", False):
                wiki_score += 3
                feedback.append("Wiki has action items / carry-over section.")

            if wiki_score == 0:
                feedback.append("Wiki content missing all expected retrospective keywords.")
            score += wiki_score
    else:
        feedback.append("Wiki page 'Sprint 1 Retrospective' NOT found.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
