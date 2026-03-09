#!/usr/bin/env python3
"""
Verifier for Cherry-Pick Security Fix task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cherry_pick_security_fix(traj, env_info, task_info):
    """
    Verifies that the security fix was cherry-picked to main.
    
    Criteria:
    1. src/api/search.js on main contains the fix (parameterized query).
    2. src/api/endpoints.js does NOT exist on main.
    3. src/api/ratelimit.js does NOT exist on main.
    4. A new commit exists on main.
    5. VLM/Metadata: Confirm commit message suggests cherry-pick or fix.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy access failed"}

    # Define paths
    result_remote_path = r"C:\Users\Docker\task_results\cherry_pick_result.json"
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Try both path styles just in case
        try:
            copy_from_env(result_remote_path, temp_file.name)
        except Exception:
            copy_from_env(result_remote_path.replace("\\", "/"), temp_file.name)
            
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve verification results. Did the export script run? Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Verify Fix Content (40 pts) ---
    search_content = result.get('search_js_content', '')
    if search_content and '@searchTerm' in search_content and 'request.input' in search_content:
        score += 40
        feedback.append("Security fix successfully applied to search.js.")
    elif search_content and '${query}' in search_content:
        feedback.append("FAIL: search.js still contains vulnerable string interpolation.")
    else:
        feedback.append("FAIL: search.js content is missing or incorrect.")

    # --- Criterion 2: Verify Unwanted File Exclusion (40 pts) ---
    # We want endpoints_js_exists = False and ratelimit_js_exists = False
    unwanted_files_present = False
    
    if not result.get('endpoints_js_exists', True):
        score += 20
        feedback.append("Correctly excluded endpoints.js.")
    else:
        unwanted_files_present = True
        feedback.append("FAIL: endpoints.js found on main (should not be included).")
        
    if not result.get('ratelimit_js_exists', True):
        score += 20
        feedback.append("Correctly excluded ratelimit.js.")
    else:
        unwanted_files_present = True
        feedback.append("FAIL: ratelimit.js found on main (should not be included).")

    # --- Criterion 3: Verify Commit History (20 pts) ---
    # Check if a new commit was added (top of list is usually newest)
    commits = result.get('commits_on_main', [])
    
    # We expect at least 2 commits (Initial + CherryPick)
    # If the user did a merge, there might be more, but we penalized unwanted files above.
    
    if len(commits) > 1:
        latest_commit = commits[0]
        msg = latest_commit.get('comment', '').lower()
        
        # Check for evidence of work
        if 'fix' in msg or 'sql' in msg or 'cherry' in msg:
            score += 20
            feedback.append(f"New commit found: '{latest_commit.get('comment')}'")
        else:
            # If they just committed "update", give partial points if content is correct
            score += 10
            feedback.append("New commit found, but message is generic.")
    else:
        feedback.append("No new commits detected on main branch.")

    # --- Final Scoring ---
    # Pass threshold: 60. 
    # Must have the fix (40) and at least one exclusion correct (20) = 60.
    # OR Fix (40) + Commit (20) = 60 (but allows dirty main).
    # Strict passing: Fix + Exclusions.
    
    passed = score >= 80  # Require Fix (40) + Both Exclusions (40)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "fix_applied": score >= 40,
            "clean_cherry_pick": not unwanted_files_present
        }
    }