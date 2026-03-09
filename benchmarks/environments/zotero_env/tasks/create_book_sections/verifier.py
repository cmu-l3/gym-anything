#!/usr/bin/env python3
"""
Verifier for create_book_sections task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_book_sections(traj, env_info, task_info):
    """
    Verify the Zotero library contains the correctly formatted Book and Book Sections.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/safe_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Parent Item converted to Book (20 pts)
    if result.get("parent_is_book"):
        score += 20
        feedback_parts.append("Parent item converted to Book")
    else:
        feedback_parts.append("Parent item NOT found as Book")

    # 2. Weaver Section (40 pts total)
    if result.get("weaver_section_found"):
        score += 10
        feedback_parts.append("Weaver section created")
        
        if result.get("weaver_pages_correct"):
            score += 15
            feedback_parts.append("Weaver pages correct")
        else:
            feedback_parts.append("Weaver pages incorrect")
            
        if result.get("weaver_author_correct"):
            score += 15
            feedback_parts.append("Weaver author correct")
        else:
            feedback_parts.append("Weaver author incorrect (check duplicates?)")
    else:
        feedback_parts.append("Weaver section NOT found")

    # 3. Shannon Section (40 pts total)
    if result.get("shannon_section_found"):
        score += 10
        feedback_parts.append("Shannon section created")
        
        if result.get("shannon_pages_correct"):
            score += 15
            feedback_parts.append("Shannon pages correct")
        else:
            feedback_parts.append("Shannon pages incorrect")
            
        if result.get("shannon_author_correct"):
            score += 15
            feedback_parts.append("Shannon author correct")
        else:
            feedback_parts.append("Shannon author incorrect")
    else:
        feedback_parts.append("Shannon section NOT found")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }