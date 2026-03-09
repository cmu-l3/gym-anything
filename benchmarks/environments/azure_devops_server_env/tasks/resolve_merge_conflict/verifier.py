#!/usr/bin/env python3
"""
Verifier for resolve_merge_conflict task.

Verifies:
1. PR status is 'completed' (25 pts)
2. File content is valid JSON (10 pts)
3. No conflict markers (10 pts)
4. Key fields match expected merged state (45 pts)
5. Work was actually done (timestamp check) (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_merge_conflict(traj, env_info, task_info):
    """
    Verify the merge conflict resolution.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path in container/VM
        copy_from_env("C:/Users/Docker/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check PR Status (25 pts)
    pr_status = result.get('pr_status', '').lower()
    if pr_status == 'completed':
        score += 25
        feedback_parts.append("PR completed successfully")
    elif pr_status == 'active':
        feedback_parts.append("PR is still active (not merged)")
    elif pr_status == 'abandoned':
        feedback_parts.append("PR was abandoned")
    else:
        feedback_parts.append(f"PR status: {pr_status}")

    # 2. JSON Validity & Conflict Markers (20 pts)
    valid_json = result.get('file_content_valid', False)
    conflict_markers = result.get('conflict_markers_found', True)
    
    if valid_json:
        score += 10
        feedback_parts.append("Valid JSON")
    else:
        feedback_parts.append("Invalid JSON content")

    if not conflict_markers:
        score += 10
    else:
        feedback_parts.append("Conflict markers (<<<<<<<) found in file")

    # 3. Content Verification (45 pts)
    # Only verify content if JSON is valid to avoid crashing
    content_check = result.get('content_check', {})
    
    if content_check.get('base_url_v2', False):
        score += 15
        feedback_parts.append("Correct BaseUrl (v2) preserved")
    else:
        feedback_parts.append("Wrong BaseUrl (expected v2)")

    if content_check.get('api_version_exists', False):
        score += 15
        feedback_parts.append("ApiVersion field preserved")
    else:
        feedback_parts.append("ApiVersion field missing")

    if content_check.get('retry_policy_exists', False):
        score += 15
        feedback_parts.append("RetryPolicy correctly added")
    else:
        feedback_parts.append("RetryPolicy missing or incorrect")

    # 4. Anti-Gaming / Commit Validation (10 pts)
    # Check if a new commit was actually made
    if result.get('commit_history_valid', False):
        score += 10
    else:
        feedback_parts.append("No new commit detected after task start")

    # Pass Threshold
    passed = score >= 60 and pr_status == 'completed' and valid_json

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }