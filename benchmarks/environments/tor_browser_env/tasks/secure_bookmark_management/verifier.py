#!/usr/bin/env python3
"""Verifier for secure_bookmark_management task.

An investigative journalist builds an organized bookmark library in Tor Browser.
Checks for correct folder names, bookmark titles, URLs, and visit history.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "secure_bookmark_management"


def verify_secure_bookmark_management(traj, env_info, task_info):
    """
    Scoring (100 points):
    1. Browser history contains check.torproject.org visit    - 10 pts
    2. Browser history contains DuckDuckGo onion visit        - 10 pts
    3. Browser history contains DuckDuckGo onion search       - 10 pts
    4. Folder 'Secure Research Sources' exists                - 15 pts  [REQUIRED]
    5. DuckDuckGo onion bookmarked in 'Secure Research Sources' - 15 pts
    6. Bookmark title 'DuckDuckGo Private Search' correct     - 10 pts
    7. check.torproject.org bookmarked in 'Secure Research Sources' - 10 pts
    8. Bookmark title 'Tor Exit Node Checker' correct         - 5 pts
    9. Folder 'Press Freedom Research' exists                 - 10 pts
    10. At least 1 bookmark in 'Press Freedom Research'       - 5 pts

    Pass threshold: 60+ points AND criterion 4 (Secure Research Sources folder) met
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

    # Gate: places.sqlite must exist
    if not result.get('db_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Tor Browser places.sqlite not found — browser not used"
        }

    score = 0
    feedback_parts = []

    # Criterion 1: History has check.torproject.org
    if result.get('history_has_check_torproject', False):
        score += 10
        feedback_parts.append("Visited check.torproject.org (10/10)")
    else:
        feedback_parts.append("check.torproject.org NOT in history (0/10)")

    # Criterion 2: History has DuckDuckGo onion
    if result.get('history_has_ddg_onion', False):
        score += 10
        feedback_parts.append("Visited DuckDuckGo onion (10/10)")
    else:
        feedback_parts.append("DuckDuckGo onion NOT in history (0/10)")

    # Criterion 3: History has DuckDuckGo onion search
    if result.get('history_has_ddg_search', False):
        score += 10
        feedback_parts.append("Performed search on DuckDuckGo onion (10/10)")
    else:
        feedback_parts.append("No DuckDuckGo onion search found in history (0/10)")

    # Criterion 4: Folder 'Secure Research Sources' exists [REQUIRED for pass]
    folder_secure = result.get('folder_secure_research', False)
    if folder_secure:
        score += 15
        feedback_parts.append("Folder 'Secure Research Sources' created (15/15)")
    else:
        feedback_parts.append("Folder 'Secure Research Sources' NOT found (0/15)")

    # Criterion 5: DuckDuckGo onion bookmarked in 'Secure Research Sources'
    if result.get('bookmark_ddg_onion_in_secure_folder', False):
        score += 15
        feedback_parts.append("DuckDuckGo onion in 'Secure Research Sources' (15/15)")
    else:
        feedback_parts.append("DuckDuckGo onion NOT in 'Secure Research Sources' (0/15)")

    # Criterion 6: Bookmark title 'DuckDuckGo Private Search' correct
    if result.get('ddg_onion_title_correct', False):
        score += 10
        feedback_parts.append("DuckDuckGo bookmark title = 'DuckDuckGo Private Search' (10/10)")
    else:
        feedback_parts.append("DuckDuckGo bookmark title incorrect (0/10)")

    # Criterion 7: check.torproject.org bookmarked in 'Secure Research Sources'
    if result.get('bookmark_tor_checker_in_secure_folder', False):
        score += 10
        feedback_parts.append("check.torproject.org in 'Secure Research Sources' (10/10)")
    else:
        feedback_parts.append("check.torproject.org NOT in 'Secure Research Sources' (0/10)")

    # Criterion 8: Bookmark title 'Tor Exit Node Checker' correct
    if result.get('tor_checker_title_correct', False):
        score += 5
        feedback_parts.append("Tor checker title = 'Tor Exit Node Checker' (5/5)")
    else:
        feedback_parts.append("Tor checker title incorrect (0/5)")

    # Criterion 9: Folder 'Press Freedom Research' exists
    if result.get('folder_press_freedom', False):
        score += 10
        feedback_parts.append("Folder 'Press Freedom Research' created (10/10)")
    else:
        feedback_parts.append("Folder 'Press Freedom Research' NOT found (0/10)")

    # Criterion 10: At least 1 bookmark in 'Press Freedom Research'
    if result.get('bookmark_in_press_freedom_folder', False):
        score += 5
        feedback_parts.append("Bookmark in 'Press Freedom Research' (5/5)")
    else:
        feedback_parts.append("No bookmarks in 'Press Freedom Research' (0/5)")

    # Pass: score >= 60 AND folder 'Secure Research Sources' exists
    passed = score >= 60 and folder_secure

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "history_torproject": 10 if result.get('history_has_check_torproject') else 0,
            "history_ddg_onion": 10 if result.get('history_has_ddg_onion') else 0,
            "history_ddg_search": 10 if result.get('history_has_ddg_search') else 0,
            "folder_secure_research": 15 if folder_secure else 0,
            "ddg_in_secure_folder": 15 if result.get('bookmark_ddg_onion_in_secure_folder') else 0,
            "ddg_title": 10 if result.get('ddg_onion_title_correct') else 0,
            "torchecker_in_secure_folder": 10 if result.get('bookmark_tor_checker_in_secure_folder') else 0,
            "torchecker_title": 5 if result.get('tor_checker_title_correct') else 0,
            "folder_press_freedom": 10 if result.get('folder_press_freedom') else 0,
            "bookmark_in_press_freedom": 5 if result.get('bookmark_in_press_freedom_folder') else 0,
        }
    }
