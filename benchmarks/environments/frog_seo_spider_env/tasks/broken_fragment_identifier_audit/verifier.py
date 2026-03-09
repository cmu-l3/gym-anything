#!/usr/bin/env python3
"""
Verifier for broken_fragment_identifier_audit task.

Checks:
1. Export CSV exists and was created during task.
2. Export CSV contains URLs with '#' characters (proof that Fragment Crawling was enabled).
3. Export CSV contains the specific known broken bookmark from crawler-test.com.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_broken_fragment_audit(traj, env_info, task_info):
    """
    Verify that the agent enabled fragment crawling and exported broken bookmarks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. File Creation (20 pts)
    # Did the agent export a CSV?
    file_created = result.get('file_created', False)
    if file_created:
        score += 20
        feedback_parts.append("Export file created")
    else:
        feedback_parts.append("No export file found")

    # 2. Fragment Config Verification (40 pts) - CRITICAL
    # Without enabling the config, SF strips '#' from URLs.
    # Presence of '#' in the CSV proves the setting was changed.
    fragment_verified = result.get('fragment_config_verified', False)
    if fragment_verified:
        score += 40
        feedback_parts.append("Fragment crawling enabled (URLs with '#' found)")
    elif file_created:
        feedback_parts.append("Fragment crawling likely NOT enabled (URLs stripped of '#')")
    else:
        feedback_parts.append("Cannot verify configuration without export")

    # 3. Content Accuracy (20 pts)
    # Did it find the specific test case?
    bookmark_found = result.get('broken_bookmark_found', False)
    if bookmark_found:
        score += 20
        feedback_parts.append("Specific broken bookmark found")
    else:
        feedback_parts.append("Broken bookmark target not identified in export")
    
    # 4. Process/Running (20 pts)
    # Was the app running? (Implies crawl attempt)
    app_running = result.get('screaming_frog_running', False)
    row_count = result.get('row_count', 0)
    
    if app_running or row_count > 0:
        score += 20
        feedback_parts.append("Crawl process active/completed")
    else:
        feedback_parts.append("Screaming Frog not running")

    # Final logic
    # Must have enabled config and produced file to pass
    passed = score >= 80 and fragment_verified and file_created

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }