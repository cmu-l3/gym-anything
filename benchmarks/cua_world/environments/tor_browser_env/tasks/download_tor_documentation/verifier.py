#!/usr/bin/env python3
"""Verifier for download_tor_documentation task.

A security researcher downloads official Tor specifications for offline reference.
Verifies the file was downloaded, saved correctly, and key navigations happened.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "download_tor_documentation"


def verify_download_tor_documentation(traj, env_info, task_info):
    """
    Scoring (100 points):
    1. File exists at /home/ga/Documents/tor-dir-spec.txt     - 30 pts  [REQUIRED]
    2. File was created after task start (is new)             - 15 pts
    3. File contains Tor specification content                - 15 pts
    4. History contains visit to spec.torproject.org          - 15 pts
    5. History contains visit to torproject.org/about/history - 10 pts
    6. Bookmark for spec.torproject.org exists                - 10 pts
    7. Bookmark title = 'Tor Protocol Specifications'         - 5 pts

    Pass threshold: 60+ points AND file exists (criterion 1)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
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

    logger.info(f"Result: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    # Criterion 1: File exists at correct path [REQUIRED for pass]
    file_exists = result.get('file_exists', False)
    if file_exists:
        score += 30
        feedback_parts.append("File /home/ga/Documents/tor-dir-spec.txt exists (30/30)")
    else:
        feedback_parts.append("File NOT found at /home/ga/Documents/tor-dir-spec.txt (0/30)")

    # Criterion 2: File is new (created after task start)
    file_is_new = result.get('file_is_new', False)
    if file_is_new:
        score += 15
        feedback_parts.append("File is newly created (15/15)")
    else:
        feedback_parts.append("File predates task start — may be stale (0/15)")

    # Criterion 3: File has Tor content
    file_has_content = result.get('file_has_tor_content', False)
    file_size = result.get('file_size', 0)
    if file_has_content and file_size > 1000:
        score += 15
        feedback_parts.append(f"File contains Tor specification content ({file_size}B) (15/15)")
    elif file_exists and file_size > 0:
        score += 7
        feedback_parts.append(f"File exists but may not be correct content ({file_size}B) (7/15)")
    else:
        feedback_parts.append("File missing or empty (0/15)")

    # Criterion 4: History has spec.torproject.org
    if result.get('history_has_spec_torproject', False):
        score += 15
        feedback_parts.append("Visited spec.torproject.org (15/15)")
    else:
        feedback_parts.append("spec.torproject.org NOT in history (0/15)")

    # Criterion 5: History has torproject.org/about/history
    if result.get('history_has_tor_history_page', False):
        score += 10
        feedback_parts.append("Visited torproject.org/about/history (10/10)")
    else:
        feedback_parts.append("torproject.org/about/history NOT in history (0/10)")

    # Criterion 6: Bookmark for spec.torproject.org
    if result.get('bookmark_spec_torproject', False):
        score += 10
        feedback_parts.append("spec.torproject.org bookmarked (10/10)")
    else:
        feedback_parts.append("spec.torproject.org NOT bookmarked (0/10)")

    # Criterion 7: Correct bookmark title
    if result.get('bookmark_spec_title_correct', False):
        score += 5
        feedback_parts.append("Bookmark title = 'Tor Protocol Specifications' (5/5)")
    else:
        feedback_parts.append("Bookmark title incorrect or missing (0/5)")

    # Pass: score >= 60 AND file exists
    passed = score >= 60 and file_exists

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "file_exists": 30 if file_exists else 0,
            "file_is_new": 15 if file_is_new else 0,
            "file_content": 15 if (file_has_content and file_size > 1000) else (7 if file_exists and file_size > 0 else 0),
            "history_spec": 15 if result.get('history_has_spec_torproject') else 0,
            "history_about": 10 if result.get('history_has_tor_history_page') else 0,
            "bookmark_exists": 10 if result.get('bookmark_spec_torproject') else 0,
            "bookmark_title": 5 if result.get('bookmark_spec_title_correct') else 0,
        }
    }
