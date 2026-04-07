#!/usr/bin/env python3
"""
Verifier for lock_and_comment_document@1.
Checks Nuxeo document state for lock status and comments content.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils if available in environment, otherwise mock or ignore
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    sample_trajectory_frames = lambda x, n: []
    get_final_screenshot = lambda x: None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_nuxeo_time(time_str):
    """Parse Nuxeo timestamp format: 2023-10-27T10:00:00.000Z"""
    if not time_str:
        return 0
    try:
        # Simplified parsing
        dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
        return dt.timestamp()
    except Exception:
        return 0

def verify_lock_and_comment(traj, env_info, task_info):
    """
    Verify the agent locked the document and left a compliance comment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # 1. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic checks
    if not result.get("doc_found"):
        return {"passed": False, "score": 0, "feedback": "Target document 'Contract Template' could not be queried."}

    score = 0
    feedback = []
    task_start = result.get("task_start", 0)

    # ----------------------------------------------------------------
    # Criterion 1: Document is Locked (35 pts)
    # ----------------------------------------------------------------
    lock_owner = result.get("lock_owner")
    lock_created_str = result.get("lock_created")
    is_locked = bool(lock_owner)
    
    if is_locked:
        score += 35
        feedback.append(f"Document is locked by {lock_owner}.")
    else:
        feedback.append("Document is NOT locked.")

    # ----------------------------------------------------------------
    # Criterion 2: Comment Exists (25 pts)
    # ----------------------------------------------------------------
    comments = result.get("comments", [])
    has_comment = len(comments) > 0
    
    if has_comment:
        score += 25
        feedback.append(f"Found {len(comments)} comment(s).")
    else:
        feedback.append("No comments found on document.")

    # ----------------------------------------------------------------
    # Criterion 3: Comment Content Quality (20 pts)
    # ----------------------------------------------------------------
    metadata = task_info.get("metadata", {})
    keywords = metadata.get("expected_keywords", ["compliance", "review", "locked"])
    
    content_valid = False
    matching_texts = []
    
    for c in comments:
        # Text can be in 'text' or properties 'comment:text'
        text = c.get("text", "")
        if not text and "properties" in c:
            text = c["properties"].get("comment:text", "")
            
        text_lower = text.lower()
        matches = [kw for kw in keywords if kw in text_lower]
        
        if len(matches) >= metadata.get("min_keywords_required", 2):
            content_valid = True
            matching_texts.append(text)
            break
            
    if content_valid:
        score += 20
        feedback.append("Comment text contains required keywords.")
    elif has_comment:
        feedback.append("Comment exists but text does not match requirements.")

    # ----------------------------------------------------------------
    # Criterion 4: Anti-Gaming / Timestamp Check (10 pts)
    # ----------------------------------------------------------------
    # Verify the lock was created AFTER the task started
    anti_gaming_pass = False
    if is_locked and lock_created_str:
        lock_ts = parse_nuxeo_time(lock_created_str)
        # Allow slight clock skew (e.g. 5 seconds)
        if lock_ts > (task_start - 5):
            anti_gaming_pass = True
            score += 10
            feedback.append("Verified lock was applied during task session.")
        else:
            feedback.append(f"Lock timestamp ({lock_created_str}) predates task start.")
    elif is_locked:
        # If locked but no timestamp (unlikely), partial credit? No, strict.
        feedback.append("Could not verify lock timestamp.")
    else:
        # Not locked, so this criterion N/A (0 pts)
        pass

    # ----------------------------------------------------------------
    # Criterion 5: Both Actions Completed (10 pts)
    # ----------------------------------------------------------------
    if is_locked and has_comment:
        score += 10
        feedback.append("Bonus: Both lock and comment actions completed.")

    # ----------------------------------------------------------------
    # Final Scoring
    # ----------------------------------------------------------------
    # Threshold: Need 60 points to pass.
    # Min path to pass: Locked (35) + Comment (25) = 60
    # Perfect path: 35 + 25 + 20 + 10 + 10 = 100
    
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }