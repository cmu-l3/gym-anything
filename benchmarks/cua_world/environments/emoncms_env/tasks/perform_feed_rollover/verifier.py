#!/usr/bin/env python3
"""
Verifier for perform_feed_rollover task.

Criteria:
1. 'annual_yield_archive' feed exists and has the ID of the ORIGINAL feed.
2. 'annual_yield' feed exists and has a NEW ID (different from original).
3. 'solar_yield' input is configured to log to the NEW 'annual_yield' feed ID.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_feed_rollover(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Extract data
    initial_id = int(result.get('initial_feed_id', -1))
    current_yield_id = int(result.get('current_yield_id', 0))
    archive_yield_id = int(result.get('archive_yield_id', 0))
    logged_feed_id = int(result.get('logged_feed_id', 0))
    input_exists = result.get('input_exists', False)

    score = 0
    feedback = []
    
    # Check 1: Input exists (Pre-req)
    if not input_exists:
        return {"passed": False, "score": 0, "feedback": "Input 'solar_yield' was deleted or missing."}

    # Check 2: Archiving Correctness (25 pts)
    # The 'annual_yield_archive' feed should exist and its ID should match the INITIAL feed ID
    # (since the user was supposed to RENAME the existing feed).
    if archive_yield_id > 0:
        if archive_yield_id == initial_id:
            score += 25
            feedback.append("Successfully archived old feed (renamed correctly).")
        else:
            # If they created a NEW archive feed and copied data (unlikely/hard), or renamed wrong one
            score += 10
            feedback.append("Archive feed exists, but ID does not match original (did you create new instead of renaming?).")
    else:
        feedback.append("Feed 'annual_yield_archive' not found.")

    # Check 3: New Feed Creation (25 pts)
    # 'annual_yield' should exist and be DIFFERENT from initial ID
    if current_yield_id > 0:
        if current_yield_id != initial_id:
            score += 25
            feedback.append("New 'annual_yield' feed created successfully.")
        else:
            feedback.append("Feed 'annual_yield' exists but has original ID (did not rename/create new).")
    else:
        feedback.append("Feed 'annual_yield' not found.")

    # Check 4: Pipeline Configuration (50 pts)
    # The input should log to the NEW 'annual_yield' feed ID
    if logged_feed_id > 0:
        if logged_feed_id == current_yield_id and current_yield_id != initial_id:
            score += 50
            feedback.append("Input correctly configured to log to the new feed.")
        elif logged_feed_id == initial_id:
            feedback.append("Input is still logging to the OLD feed (archive).")
        elif logged_feed_id == archive_yield_id:
            feedback.append("Input is logging to the archive feed.")
        else:
            feedback.append(f"Input is logging to unknown feed ID {logged_feed_id}.")
    else:
        feedback.append("Input does not have a 'Log to feed' process.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }