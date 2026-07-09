"""Verifier for safari_federal_accessibility_audit."""

from __future__ import annotations

import json
import os
import tempfile

REMOTE_RESULT  = "/tmp/federal_accessibility_audit_result.json"
REQUIRED_SITES = ["ssa.gov", "medicare.gov", "va.gov", "benefits.gov"]


def verify_safari_federal_accessibility_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    tmp.close()
    try:
        copy_from_env(REMOTE_RESULT, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}",
        }
    finally:
        os.unlink(tmp.name)

    history      = result.get("history", {})
    total_visits = sum(history.values())
    report_exists = result.get("report_exists", False)

    # ── Gate 1: no work ───────────────────────────────────────────────────────
    if total_visits == 0 and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No .gov site visits and no output file found. Agent did not attempt the task.",
        }

    # ── Gate 2: must have visited at least one target site ───────────────────
    sites_visited = [k for k, v in history.items() if v > 0]
    if not sites_visited:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "None of the four required .gov sites were visited. "
                "The task requires using Safari's Web Inspector Audit on ssa.gov, "
                "medicare.gov, va.gov, and benefits.gov."
            ),
        }

    # ── Gate 3: output file ───────────────────────────────────────────────────
    if not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "federal_accessibility_audit.json not found in ~/Documents/.",
        }

    if not result.get("report_written_after_start", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file predates task setup — stale file.",
        }

    if result.get("parse_error"):
        return {
            "passed": False,
            "score": 5,
            "feedback": f"Output file is not valid JSON: {result['parse_error']}",
        }

    # ── Scoring ───────────────────────────────────────────────────────────────
    # 10 pts: ≥1 site entry found
    # 15 pts: ≥2 sites visited in browser (history)
    # 15 pts: ≥1 site with full data (total, breakdown, 3 descriptions)
    # 30 pts: ≥3 sites complete
    # 30 pts: all 4 sites complete
    score = 0
    subscores = {}
    feedback_parts = []

    sites_found    = result.get("sites_found", [])
    sites_complete = result.get("sites_complete", [])
    site_details   = result.get("site_details", {})

    if sites_found:
        score += 10
        subscores["sites_present"] = 10
    else:
        subscores["sites_present"] = 0
        feedback_parts.append("No recognised .gov site entries found in output JSON.")

    visited_count = sum(1 for v in history.values() if v > 0)
    if visited_count >= 2:
        score += 15
        subscores["two_sites_visited"] = 15
    else:
        subscores["two_sites_visited"] = 0
        feedback_parts.append(f"Only {visited_count} target site(s) visited in browser history.")

    if len(sites_complete) >= 1:
        score += 15
        subscores["one_site_complete"] = 15
    else:
        subscores["one_site_complete"] = 0
        feedback_parts.append(
            "No site has all required fields: total_issues count, error/warning/comment breakdown, "
            "and at least 3 specific issue descriptions."
        )

    if len(sites_complete) >= 3:
        score += 30
        subscores["three_sites_complete"] = 30
    else:
        subscores["three_sites_complete"] = 0
        missing = [s for s in REQUIRED_SITES if s not in sites_complete]
        feedback_parts.append(f"Incomplete sites: {missing}.")

    if len(sites_complete) == 4:
        score += 30
        subscores["all_four_complete"] = 30
    else:
        subscores["all_four_complete"] = 0

    # Per-site detail
    for site in sites_found:
        detail = site_details.get(site, {})
        issues = []
        if not detail.get("has_total"):
            issues.append("missing total_issues count")
        if not detail.get("has_breakdown"):
            issues.append("missing error/warning/comment breakdown")
        if not detail.get("has_3_descs"):
            dc = detail.get("desc_count", 0)
            issues.append(f"only {dc} issue description(s) found, need ≥3")
        if issues:
            feedback_parts.append(f"{site}: {'; '.join(issues)}.")

    passed = score >= 70
    summary = f"Score {score}/100. {len(sites_complete)} of 4 sites fully documented."
    feedback = summary + (" " + " ".join(feedback_parts) if feedback_parts else "")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
    }
