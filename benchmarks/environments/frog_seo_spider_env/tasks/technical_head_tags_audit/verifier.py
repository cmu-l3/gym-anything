#!/usr/bin/env python3
"""Verifier for Technical Head Tags Audit task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_technical_head_tags_audit(traj, env_info, task_info):
    """Verify technical head tags audit task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # Criterion 1: File created (20 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 20
        feedback_parts.append("File created (20/20)")
    else:
        feedback_parts.append("File not created or stale (0/20)")

    # Criterion 2: Data Volume (10 pts)
    # Require at least some rows to prove crawl happened
    rows = result.get('row_count', 0)
    if rows >= 20:
        score += 10
        feedback_parts.append(f"Row count {rows} OK (10/10)")
    elif rows > 0:
        score += 5
        feedback_parts.append(f"Row count {rows} low (5/10)")
    else:
        feedback_parts.append("Empty file (0/10)")

    # Criterion 3: Viewport Data (25 pts)
    if result.get('has_viewport_data'):
        score += 25
        feedback_parts.append("Viewport extracted (25/25)")
    else:
        feedback_parts.append("Viewport missing (0/25)")

    # Criterion 4: Favicon Data (25 pts)
    if result.get('has_favicon_data'):
        score += 25
        feedback_parts.append("Favicon extracted (25/25)")
    else:
        feedback_parts.append("Favicon missing (0/25)")

    # Criterion 5: Charset Data (20 pts)
    if result.get('has_charset_data'):
        score += 20
        feedback_parts.append("Charset extracted (20/20)")
    else:
        feedback_parts.append("Charset missing (0/20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }