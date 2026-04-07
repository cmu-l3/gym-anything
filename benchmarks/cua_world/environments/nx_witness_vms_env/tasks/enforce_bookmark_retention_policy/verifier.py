#!/usr/bin/env python3
"""
Verifier for enforce_bookmark_retention_policy task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_retention_policy(traj, env_info, task_info):
    """
    Verifies that the agent correctly applied the retention policy.
    
    Scoring:
    - 40 pts: All bookmarks that SHOULD be deleted ARE deleted.
    - 30 pts: All "LegalHold" bookmarks that SHOULD be kept ARE kept.
    - 20 pts: All "New" bookmarks that SHOULD be kept ARE kept.
    - 10 pts: Log file created and contains data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse Data
    final_bookmarks = result.get('final_bookmarks', [])
    ground_truth = result.get('ground_truth', [])
    log_exists = result.get('log_file_exists', False)
    log_content = result.get('log_content', "")

    # Create a set of remaining IDs for O(1) lookup
    remaining_ids = set(b.get('id') for b in final_bookmarks)

    score = 0
    feedback = []

    # 1. Check Deletions (Target: Old + No Hold)
    should_delete_items = [b for b in ground_truth if b['expected_deleted']]
    deleted_correctly_count = 0
    
    for item in should_delete_items:
        if item['id'] not in remaining_ids:
            deleted_correctly_count += 1
        else:
            feedback.append(f"FAILED to delete old bookmark: {item['description']} ({item['age_days']} days old)")

    if len(should_delete_items) > 0:
        if deleted_correctly_count == len(should_delete_items):
            score += 40
            feedback.append("Successfully deleted all expired bookmarks.")
        else:
            # Partial credit
            partial = int(40 * (deleted_correctly_count / len(should_delete_items)))
            score += partial
            feedback.append(f"Deleted {deleted_correctly_count}/{len(should_delete_items)} expired bookmarks.")

    # 2. Check Safety - LegalHold (Target: Old + Hold)
    should_keep_hold = [b for b in ground_truth if not b['expected_deleted'] and 'legalhold' in b['description'].lower()]
    kept_hold_count = 0
    
    for item in should_keep_hold:
        if item['id'] in remaining_ids:
            kept_hold_count += 1
        else:
            feedback.append(f"WRONGFULLY deleted LegalHold bookmark: {item['description']}")

    if len(should_keep_hold) > 0:
        if kept_hold_count == len(should_keep_hold):
            score += 30
            feedback.append("Correctly preserved all LegalHold bookmarks.")
        else:
            # High penalty for deleting legal holds (safety violation)
            # Only give credit if ALL are kept? Or proportional? Let's do proportional but strict.
            partial = int(30 * (kept_hold_count / len(should_keep_hold)))
            score += partial

    # 3. Check Safety - Recent (Target: New + No Hold)
    should_keep_recent = [b for b in ground_truth if not b['expected_deleted'] and 'legalhold' not in b['description'].lower()]
    kept_recent_count = 0
    
    for item in should_keep_recent:
        if item['id'] in remaining_ids:
            kept_recent_count += 1
        else:
            feedback.append(f"WRONGFULLY deleted recent bookmark: {item['description']} ({item['age_days']} days old)")

    if len(should_keep_recent) > 0:
        if kept_recent_count == len(should_keep_recent):
            score += 20
            feedback.append("Correctly preserved all recent bookmarks.")
        else:
            partial = int(20 * (kept_recent_count / len(should_keep_recent)))
            score += partial

    # 4. Log File
    if log_exists and len(log_content.strip()) > 5:
        score += 10
        feedback.append("Log file created.")
    elif log_exists:
        score += 5
        feedback.append("Log file created but empty.")
    else:
        feedback.append("Log file missing.")

    # Final Pass Decision
    # Strict threshold: Must score at least 90. 
    # This implies they must get ALMOST everything right. 
    # Specifically, deleting legal holds is a major failure.
    passed = score >= 90

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }