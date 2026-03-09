#!/usr/bin/env python3
"""
Verifier for catalog_and_link_dataset task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_catalog_and_link_dataset(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Dataset Item Created (20 pts)
    if result.get("dataset_found"):
        score += 20
        feedback_parts.append("Dataset item created")
    else:
        feedback_parts.append("Dataset item NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Metadata Checks (40 pts)
    # Title (10)
    if result.get("title_correct"):
        score += 10
        feedback_parts.append("Title correct")
    else:
        feedback_parts.append("Title incorrect")

    # Author (10)
    if result.get("author_found"):
        score += 10
        feedback_parts.append("Author correct")
    else:
        feedback_parts.append("Author incorrect/missing")

    # Date/URL (10)
    if result.get("date_correct") and result.get("url_correct"):
        score += 10
        feedback_parts.append("Date & URL correct")
    elif result.get("date_correct") or result.get("url_correct"):
        score += 5
        feedback_parts.append("Date or URL correct")
    else:
        feedback_parts.append("Date/URL incorrect")

    # Repository (10)
    if result.get("repository_correct"):
        score += 10
        feedback_parts.append("Repository correct")
    else:
        feedback_parts.append("Repository incorrect/missing")

    # 3. Relation Established (40 pts)
    if result.get("relation_found"):
        score += 40
        feedback_parts.append("Link to paper established")
    else:
        feedback_parts.append("Link to paper NOT found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }