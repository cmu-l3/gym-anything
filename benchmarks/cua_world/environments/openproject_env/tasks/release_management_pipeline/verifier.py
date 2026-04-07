#!/usr/bin/env python3
"""
Verifier for release_management_pipeline task.

Stub verifier — VLM checklist verification is the primary evaluation method.
This provides basic programmatic scoring as a supplement.

Scoring (100 pts total):
  Statuses created (3 x 4 pts)         = 12
  Workflow transitions (4 x 4 pts)     = 16
  Custom field created + values         =  8
  Custom field enabled for projects     =  4
  Project exists with config            =  8
  Members added (3 x 2 pts)            =  6
  Work packages (3 x 6 pts)            = 18
  WP status correctness                =  3
  Board exists                          = 10
  Wiki page exists + content            = 15
  Total                                 = 100
  Pass threshold                        = 55
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/task_result.json"

EXPECTED_TRANSITIONS = [
    ("In progress", "Ready for QA"),
    ("Ready for QA", "QA Passed"),
    ("QA Passed", "Staging Deployed"),
    ("Staging Deployed", "Closed"),
]

WIKI_KEYWORDS = [
    "ready for qa", "qa passed", "staging deployed",
    "v2.0.0", "v2.1.0", "v3.0.0",
    "alice", "bob", "carol",
]


def verify_release_management_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(RESULT_FILE, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # ── 1. Statuses (12 pts) ──
    statuses_found = result.get("statuses", {}).get("found", [])
    for name in ["Ready for QA", "QA Passed", "Staging Deployed"]:
        if name in statuses_found:
            score += 4
            feedback.append(f"Status '{name}' exists")
        else:
            feedback.append(f"Status '{name}' NOT found")

    # ── 2. Workflow transitions (16 pts) ──
    transitions = result.get("workflow", {}).get("transitions", [])
    transition_set = set()
    for t in transitions:
        if isinstance(t, list) and len(t) == 2:
            transition_set.add((t[0], t[1]))
    for from_s, to_s in EXPECTED_TRANSITIONS:
        if (from_s, to_s) in transition_set:
            score += 4
            feedback.append(f"Workflow '{from_s}' -> '{to_s}' configured")
        else:
            feedback.append(f"Workflow '{from_s}' -> '{to_s}' MISSING")

    # ── 3. Custom field (8 pts) ──
    cf = result.get("custom_field", {})
    if cf.get("exists"):
        score += 3
        feedback.append("Custom field 'Target Release' exists")
        cf_values = set(cf.get("values", []))
        expected_values = {"v2.0.0-alpha", "v2.1.0-beta", "v3.0.0"}
        if expected_values.issubset(cf_values):
            score += 5
            feedback.append("Custom field values correct")
        else:
            missing = expected_values - cf_values
            feedback.append(f"Custom field missing values: {missing}")
    else:
        feedback.append("Custom field 'Target Release' NOT found")

    # ── 4. Custom field enabled for projects/types (4 pts) ──
    if cf.get("exists"):
        cf_projects = set(cf.get("project_ids", []))
        expected_projects = {"ecommerce-platform", "mobile-banking-app", "devops-automation"}
        cf_types = set(cf.get("type_names", []))
        expected_types = {"Feature", "Bug"}
        if expected_projects.issubset(cf_projects):
            score += 2
            feedback.append("Custom field enabled for all projects")
        else:
            feedback.append(f"Custom field missing projects: {expected_projects - cf_projects}")
        if expected_types.issubset(cf_types):
            score += 2
            feedback.append("Custom field enabled for Feature and Bug types")
        else:
            feedback.append(f"Custom field missing types: {expected_types - cf_types}")

    # ── 5. Project (8 pts) ──
    proj = result.get("project", {})
    if proj.get("exists"):
        score += 4
        feedback.append("Project 'Release Coordination' exists")
        modules = set(proj.get("modules", []))
        for m in ["work_package_tracking", "wiki", "board_view"]:
            if m in modules:
                score += 1
            else:
                feedback.append(f"Module '{m}' not enabled")
        if proj.get("is_public"):
            score += 1
            feedback.append("Project is public")
        else:
            feedback.append("Project is NOT public")
    else:
        feedback.append("Project 'Release Coordination' NOT found")

    # ── 6. Members (6 pts) ──
    members = result.get("members", {}).get("members", [])
    member_logins = {m.get("login") for m in members if m.get("login")}
    for login in ["alice.johnson", "bob.smith", "carol.williams"]:
        if login in member_logins:
            score += 2
            feedback.append(f"Member '{login}' added")
        else:
            feedback.append(f"Member '{login}' NOT found")

    # ── 7. Work packages (18 pts) + status (3 pts) ──
    wps = result.get("work_packages", {}).get("work_packages", [])
    wp_by_subject = {wp.get("subject", ""): wp for wp in wps}

    expected_wps = task_info.get("metadata", {}).get("work_packages", [])
    for ewp in expected_wps:
        subj = ewp["subject"]
        if subj in wp_by_subject:
            wp = wp_by_subject[subj]
            score += 2  # exists
            feedback.append(f"WP '{subj[:40]}...' exists")
            if wp.get("type_name") == "Feature":
                score += 1
            if wp.get("assignee") == ewp["assignee"]:
                score += 1
            if wp.get("target_release") == ewp["target_release"]:
                score += 2
                feedback.append(f"  Target Release correct: {ewp['target_release']}")
            # Status check (3 pts total, only for the first WP)
            if ewp["status"] == "In progress" and wp.get("status") == "In progress":
                score += 3
                feedback.append("  Status 'In progress' correctly set")
        else:
            feedback.append(f"WP '{subj[:40]}...' NOT found")

    # ── 8. Board (10 pts) ──
    boards = result.get("boards", {}).get("boards", [])
    target_board = None
    for b in boards:
        if b.get("name", "").lower().strip() == "release pipeline":
            target_board = b
            break
    if target_board:
        score += 5
        feedback.append("Board 'Release Pipeline' exists")
        if target_board.get("board_attribute") == "status":
            score += 3
            feedback.append("Board is status-based")
        if target_board.get("column_count", 0) >= 4:
            score += 2
            feedback.append(f"Board has {target_board['column_count']} columns")
        else:
            feedback.append(f"Board has only {target_board.get('column_count', 0)} columns")
    else:
        feedback.append("Board 'Release Pipeline' NOT found")

    # ── 9. Wiki page (15 pts) ──
    wiki = result.get("wiki", {})
    if wiki.get("exists"):
        score += 5
        feedback.append("Wiki page 'Release Management Process' exists")
        content = wiki.get("content_lower", "")
        if len(content) >= 50:
            score += 3
            feedback.append(f"Wiki content length: {wiki.get('content_length', 0)}")
            keyword_hits = sum(1 for kw in WIKI_KEYWORDS if kw in content)
            keyword_score = min(7, keyword_hits)
            score += keyword_score
            feedback.append(f"Wiki keywords matched: {keyword_hits}/{len(WIKI_KEYWORDS)}")
        else:
            feedback.append("Wiki content too short")
    else:
        feedback.append("Wiki page 'Release Management Process' NOT found")

    passed = score >= 55
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
