#!/usr/bin/env python3
"""
Verifier for Legacy Portal Access task.
Verifies that the agent retrieved the correct code by spoofing User-Agent.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_portal_access(traj, env_info, task_info):
    """
    Verify the agent successfully accessed the legacy portal and retrieved the code.
    
    Criteria:
    1. Output file exists and was created during task (10 pts)
    2. Extracted code matches ground truth exactly (50 pts)
    3. Browser history shows visit to localhost:8000 (20 pts)
    4. Server logs confirm IE User-Agent was used (10 pts)
    5. Screenshot evidence exists (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: File Existence (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("Manifest file created.")
    else:
        feedback_parts.append("Manifest file missing or stale.")

    # Check 2: Code Correctness (50 pts)
    extracted = result.get('extracted_code', '').strip()
    truth = result.get('ground_truth_code', '').strip()
    
    if extracted and truth and extracted == truth:
        score += 50
        feedback_parts.append("Code matches ground truth.")
    elif extracted:
        feedback_parts.append(f"Code incorrect. Got '{extracted}', expected '{truth}'.")
    else:
        feedback_parts.append("No code found in file.")

    # Check 3: Browser History (20 pts)
    # This proves they didn't just curl the URL with a header from the terminal (unless they were very clever)
    # Ideally we want browser interaction.
    if result.get('browser_history_visit'):
        score += 20
        feedback_parts.append("Browser history confirmed.")
    else:
        feedback_parts.append("No browser history for portal found.")

    # Check 4: Server Logs (10 pts)
    # Did the server actually receive a request with the IE UA?
    if result.get('server_log_shows_ie'):
        score += 10
        feedback_parts.append("Server confirmed legacy User-Agent.")
    else:
        feedback_parts.append("Server did not detect IE User-Agent.")

    # Check 5: Evidence Screenshot (10 pts)
    if result.get('evidence_screenshot_exists'):
        score += 10
        feedback_parts.append("Evidence screenshot found.")
    else:
        feedback_parts.append("No evidence screenshot found.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }