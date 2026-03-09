#!/usr/bin/env python3
"""
Verifier for gitflow_hotfix_propagation task.

Checks:
1. Two PRs were completed (Hotfix -> Main, Hotfix -> Develop).
2. The hotfix branch was deleted.
3. The code fix exists in both Main and Develop branches.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gitflow_hotfix_propagation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Define max points
    POINTS_PR_MAIN = 30
    POINTS_PR_DEVELOP = 30
    POINTS_BRANCH_DELETED = 20
    POINTS_CONTENT_VERIFIED = 20

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Verify PR to Main
    if result.get('main_pr_found', False):
        score += POINTS_PR_MAIN
        feedback_parts.append("PR to Main completed successfully.")
    else:
        feedback_parts.append("FAIL: No completed PR found merging hotfix to main.")

    # 2. Verify PR to Develop
    if result.get('develop_pr_found', False):
        score += POINTS_PR_DEVELOP
        feedback_parts.append("PR to Develop completed successfully.")
    else:
        feedback_parts.append("FAIL: No completed PR found merging hotfix to develop.")

    # 3. Verify Branch Deletion
    # Only award points if at least one PR was done (prevent accidental deletion without work)
    if result.get('hotfix_branch_deleted', False):
        if score > 0: 
            score += POINTS_BRANCH_DELETED
            feedback_parts.append("Hotfix branch deleted.")
        else:
            feedback_parts.append("Hotfix branch deleted, but no merge work detected.")
    else:
        feedback_parts.append("Hotfix branch still exists (should be deleted after merges).")

    # 4. Verify Content
    main_ok = result.get('main_has_fix', False)
    dev_ok = result.get('develop_has_fix', False)
    
    if main_ok and dev_ok:
        score += POINTS_CONTENT_VERIFIED
        feedback_parts.append("Fix verified in both Main and Develop.")
    elif main_ok:
        score += 10
        feedback_parts.append("Fix found in Main, but MISSING in Develop.")
    elif dev_ok:
        score += 10
        feedback_parts.append("Fix found in Develop, but MISSING in Main.")
    else:
        feedback_parts.append("Fix content not found in target branches.")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }