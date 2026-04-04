#!/usr/bin/env python3
"""
Verifier for magazine_article_review task.

Task Requirements:
1. File saved as AI_Draft_Reviewed.odt
2. Track Changes (Record Changes) Enabled
3. Title changed to "The Evolution of Generative AI"
4. Typo "Generatve" -> "Generative" corrected
5. Terminator 2 paragraph deleted
6. Comment added "Define acronym"

Scoring Strategy:
- File Exists: 10 pts
- Track Changes Enabled: 25 pts (Critical)
- Edits Performed (Tracked): 45 pts total
- Comment Added: 20 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_magazine_article_review(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback = []
    
    # 1. File Exists (10 pts)
    if result.get("file_exists", False):
        score += 10
        feedback.append("File created (+10)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Track Changes Enabled (25 pts)
    tc_enabled = result.get("track_changes_enabled", False)
    if tc_enabled:
        score += 25
        feedback.append("Track Changes enabled (+25)")
    else:
        feedback.append("Track Changes NOT enabled (Critical failure for a review task)")

    # 3. Title Change (15 pts)
    # We require the content to match AND ideally happen while tracking is on
    if result.get("title_changed", False):
        if tc_enabled:
            score += 15
            feedback.append("Title updated (+15)")
        else:
            score += 5
            feedback.append("Title updated but not tracked (+5)")
    else:
        feedback.append("Title not updated correctly")

    # 4. Typo Fix (15 pts)
    if result.get("typo_fixed", False):
        if tc_enabled:
            score += 15
            feedback.append("Typo fixed (+15)")
        else:
            score += 5
            feedback.append("Typo fixed but not tracked (+5)")
    else:
        feedback.append("Typo not fixed")

    # 5. Paragraph Deletion (15 pts)
    if result.get("paragraph_deleted", False):
        if tc_enabled:
            score += 15
            feedback.append("Paragraph deleted (+15)")
        else:
            # If text is gone but tracking off, result['paragraph_deleted'] logic in export might false negative
            # But based on our export logic, we check tracking specifically for this field
            feedback.append("Paragraph deletion not tracked correctly")
    else:
        # If tracking was OFF, the export script might have missed the deletion (text just gone)
        # We can't verify deletion easily if text is gone and tracking is off without 'before' comparison
        # Assuming export script logic handles "text gone = deleted" if implemented
        pass
        
    # 6. Comment Added (20 pts)
    if result.get("comment_added", False):
        score += 10
        if result.get("comment_text_found", False):
            score += 10
            feedback.append("Comment added with correct text (+20)")
        else:
            feedback.append("Comment added but text mismatch (+10)")
    else:
        feedback.append("No comment added")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }