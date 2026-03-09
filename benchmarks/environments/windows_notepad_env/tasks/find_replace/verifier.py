#!/usr/bin/env python3
"""
Verifier for find_replace task.
Checks if 'old' was replaced with 'new' throughout the document.
"""

import logging
import os
import tempfile
import shutil

logging.basicConfig(level=logging.DEBUG)


def check_find_replace(traj, env_info, task_info):
    """
    Verify that all occurrences of 'old' were replaced with 'new'.

    Original document has 5 occurrences of 'old'.
    Success: All replaced with 'new', no 'old' remaining.
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    temp_dir = tempfile.mkdtemp(prefix="verify_findreplace_")

    possible_paths = [
        "C:/OEM/Shared/result_document.txt",
        "C:/Users/Docker/Desktop/Tasks/document.txt",
    ]

    result_content = None

    for remote_path in possible_paths:
        try:
            local_path = os.path.join(temp_dir, "document.txt")
            copy_from_env(remote_path, local_path)

            if os.path.exists(local_path):
                with open(local_path, 'r', encoding='utf-8', errors='ignore') as f:
                    result_content = f.read()
                break
        except:
            pass

    try:
        shutil.rmtree(temp_dir)
    except:
        pass

    if result_content is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not find document.txt"
        }

    content_lower = result_content.lower()

    # Count occurrences
    old_count = content_lower.count('old')
    new_count = content_lower.count('new')

    # Original has 5 'old' and 1 'new' (in "new text")
    # After replacement: 0 'old' and 6 'new'

    feedback_parts = []

    if old_count == 0 and new_count >= 5:
        score = 100
        feedback_parts.append("All 'old' replaced with 'new' successfully!")
    elif old_count < 5 and new_count > 1:
        # Partial replacement
        replaced = 5 - old_count
        score = int((replaced / 5) * 80)
        feedback_parts.append(f"Partial replacement: {replaced}/5 occurrences replaced")
    elif old_count == 5:
        score = 0
        feedback_parts.append("No replacements made - still has 5 'old' occurrences")
    else:
        score = 20
        feedback_parts.append("Unexpected content state")

    feedback_parts.append(f"'old' count: {old_count}, 'new' count: {new_count}")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
