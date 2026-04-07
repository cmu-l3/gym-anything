#!/usr/bin/env python3
"""Verifier for configure_cookie_site_exceptions task.

Evaluates if the agent correctly applied per-site cookie exceptions (Allow/Block)
via the Tor Browser UI, verified functionality by visiting the allowed domains,
and generated the expected policy documentation.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "configure_cookie_site_exceptions"

def verify_configure_cookie_site_exceptions(traj, env_info, task_info):
    """
    Verification strategy (Total 100 points):
    1. Verify 5 exact cookie exceptions in permissions.sqlite (5 * 12 points = 60 pts)
       - check.torproject.org (Allow = 1)
       - duckduckgo.com (Allow = 1)
       - wikipedia.org (Allow = 1)
       - facebook.com (Block = 2)
       - google.com (Block = 2)
    2. Verify history contains visits to check.torproject.org and duckduckgo.com (15 pts)
    3. Verify text report exists, was created after start, and contains expected content (25 pts)

    Pass threshold: 60 points AND at least 3 correctly configured cookie exceptions (gate).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
        with open(tmp.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result JSON: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    perms = result.get('perms', [])
    history = result.get('history', [])
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    report_content = result.get('report_content', "").lower()
    task_start = result.get('task_start', 0)

    # 1. Evaluate Cookie Permissions
    tor_allow = any("check.torproject.org" in p["origin"] and p["permission"] == 1 for p in perms)
    ddg_allow = any("duckduckgo.com" in p["origin"] and p["permission"] == 1 for p in perms)
    wiki_allow = any("wikipedia.org" in p["origin"] and p["permission"] == 1 for p in perms)
    fb_block = any("facebook.com" in p["origin"] and p["permission"] == 2 for p in perms)
    google_block = any("google.com" in p["origin"] and p["permission"] == 2 for p in perms)

    correct_perms = sum([tor_allow, ddg_allow, wiki_allow, fb_block, google_block])

    if tor_allow:
        score += 12
        feedback_parts.append("Tor check allowed (12/12)")
    else:
        feedback_parts.append("Tor check NOT allowed (0/12)")

    if ddg_allow:
        score += 12
        feedback_parts.append("DuckDuckGo allowed (12/12)")
    else:
        feedback_parts.append("DuckDuckGo NOT allowed (0/12)")

    if wiki_allow:
        score += 12
        feedback_parts.append("Wikipedia allowed (12/12)")
    else:
        feedback_parts.append("Wikipedia NOT allowed (0/12)")

    if fb_block:
        score += 12
        feedback_parts.append("Facebook blocked (12/12)")
    else:
        feedback_parts.append("Facebook NOT blocked (0/12)")

    if google_block:
        score += 12
        feedback_parts.append("Google blocked (12/12)")
    else:
        feedback_parts.append("Google NOT blocked (0/12)")

    gate_passed = correct_perms >= 3

    # 2. Evaluate History Visits
    tor_visited = any("check.torproject.org" in h.lower() for h in history)
    ddg_visited = any("duckduckgo.com" in h.lower() for h in history)

    if tor_visited:
        score += 10
        feedback_parts.append("Visited check.torproject.org (10/10)")
    else:
        feedback_parts.append("Did not visit check.torproject.org (0/10)")

    if ddg_visited:
        score += 5
        feedback_parts.append("Visited duckduckgo.com (5/5)")
    else:
        feedback_parts.append("Did not visit duckduckgo.com (0/5)")

    # 3. Evaluate Policy Report
    if report_exists and report_mtime >= task_start:
        score += 10
        feedback_parts.append("Report file exists (10/10)")
        
        # Check if domains mentioned in content
        domains_found = all(d in report_content for d in ["torproject", "duckduckgo", "wikipedia", "facebook", "google"])
        if domains_found:
            score += 10
            feedback_parts.append("Report mentions all sites (10/10)")
        else:
            feedback_parts.append("Report missing some sites (0/10)")
            
        # Check if it differentiates Allow and Block
        if "allow" in report_content and "block" in report_content:
            score += 5
            feedback_parts.append("Report distinguishes Allow/Block (5/5)")
        else:
            feedback_parts.append("Report lacks Allow/Block keywords (0/5)")
    else:
        feedback_parts.append("Report file NOT found or stale (0/25)")

    passed = score >= 60 and gate_passed

    if not gate_passed:
        feedback_parts.insert(0, f"GATE FAILED: Only {correct_perms}/5 exceptions correctly configured (minimum 3 required)")

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "correct_perms_count": correct_perms,
            "tor_visited": tor_visited,
            "ddg_visited": ddg_visited,
            "report_valid": report_exists and report_mtime >= task_start
        }
    }