#!/usr/bin/env python3
"""
Verifier for academic_peer_review task.

Criteria:
1. Output file exists and was modified during task (10 pts)
2. Track Changes feature was used (20 pts)
3. Typo "Drosphila" corrected to "Drosophila" (15 pts)
4. "Nobel prize" sentence deleted via track changes (15 pts)
5. Comment regarding "citation" added (20 pts)
6. Comment regarding "Title" added (20 pts)

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_academic_peer_review(traj, env_info, task_info):
    """Verify the peer review document."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & modification (10 pts)
    if result.get("file_exists") and result.get("file_stats", {}).get("modified_during_task"):
        score += 10
        feedback_parts.append("File saved correctly")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("File exists but not modified during task?")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Track Changes Enabled (20 pts)
    if result.get("has_tracked_changes"):
        score += 20
        feedback_parts.append("Track changes enabled")
    else:
        feedback_parts.append("Track changes NOT enabled")

    # 3. Typo Correction (15 pts)
    # The agent should have replaced Drosphila with Drosophila
    content_check = result.get("content_check", {})
    if content_check.get("typo_fixed"):
        score += 15
        feedback_parts.append("Typo corrected")
    else:
        feedback_parts.append("Typo 'Drosphila' still present or not corrected properly")

    # 4. Sentence Deletion (15 pts)
    # Check if deletion was tracked
    changes = result.get("changes_found", [])
    deletion_confirmed = False
    for change in changes:
        if change["type"] == "deletion" and "Nobel prize" in change["text"]:
            deletion_confirmed = True
            break
    
    if deletion_confirmed:
        score += 15
        feedback_parts.append("Sentence deleted (tracked)")
    else:
        # Check if it was just deleted without tracking?
        # The export script logic for 'sentence_deleted' relies on finding it in tracked changes
        # So if it's False, it wasn't tracked-deleted.
        feedback_parts.append("Sentence not deleted using Track Changes")

    # 5. Comment 1: Citation (20 pts)
    comments = result.get("comments_found", [])
    citation_comment_found = False
    for c in comments:
        if "citation" in c.lower() and "provide" in c.lower():
            citation_comment_found = True
            break
            
    if citation_comment_found:
        score += 20
        feedback_parts.append("Citation comment added")
    else:
        feedback_parts.append("Citation comment missing")

    # 6. Comment 2: Title (20 pts)
    title_comment_found = False
    for c in comments:
        if "title" in c.lower() and "vague" in c.lower():
            title_comment_found = True
            break
            
    if title_comment_found:
        score += 20
        feedback_parts.append("Title comment added")
    else:
        feedback_parts.append("Title comment missing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }