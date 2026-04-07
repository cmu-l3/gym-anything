#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_granular_cookie_clearing(traj, env_info, task_info):
    """
    Verifies that the agent selectively cleared cookies for Github and StackOverflow
    while preserving Google cookies.
    """
    # 1. Boilerplate: Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Parse Data
    gh_count = int(result.get("github_cookies", -1))
    so_count = int(result.get("stackoverflow_cookies", -1))
    go_count = int(result.get("google_cookies", -1))
    db_mtime = int(result.get("db_mtime", 0))
    task_start = int(result.get("task_start_time", 0))

    score = 0
    feedback = []

    # 4. Scoring Logic
    
    # CRITERION 1: GitHub Cookies Cleared (30 pts)
    if gh_count == 0:
        score += 30
        feedback.append("GitHub cookies successfully cleared.")
    elif gh_count > 0:
        feedback.append(f"GitHub cookies still present ({gh_count} found).")
    else:
        feedback.append("Failed to read GitHub cookie count.")

    # CRITERION 2: StackOverflow Cookies Cleared (30 pts)
    if so_count == 0:
        score += 30
        feedback.append("StackOverflow cookies successfully cleared.")
    elif so_count > 0:
        feedback.append(f"StackOverflow cookies still present ({so_count} found).")

    # CRITERION 3: Google Cookies Preserved (30 pts)
    # If the agent used "Clear All Data", this will be 0, failing the task.
    if go_count > 0:
        score += 30
        feedback.append("Google cookies preserved.")
    else:
        feedback.append("CRITICAL: Google cookies were deleted! You must only delete specific sites.")

    # CRITERION 4: DB Modified (10 pts)
    # Ensures the database was actually written to during the task window
    if db_mtime > task_start:
        score += 10
        feedback.append("Database modification confirmed.")
    else:
        feedback.append("Cookies database was not modified during the task.")

    # Pass Threshold
    # They must get 100/100. Partial credit is nice for scoring, but this is a troubleshooting task
    # where deleting the wrong data (Google) is a failure.
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }