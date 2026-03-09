#!/usr/bin/env python3
"""
Verifier for save_file task.
Checks if the user successfully modified and saved the sample.txt file.
"""

import logging
import os
import tempfile
import shutil

logging.basicConfig(level=logging.DEBUG)


def check_file_saved(traj, env_info, task_info):
    """
    Verify that sample.txt was modified with the required line.

    Success criteria:
    1. File sample.txt still exists
    2. Original content is preserved
    3. New line 'This line was added by the agent.' is present
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    temp_dir = tempfile.mkdtemp(prefix="verify_save_")

    possible_paths = [
        "C:/OEM/Shared/result_sample.txt",
        "C:/Users/Docker/Desktop/Tasks/sample.txt",
    ]

    result_content = None
    found_path = None

    for remote_path in possible_paths:
        try:
            local_path = os.path.join(temp_dir, "sample.txt")
            copy_from_env(remote_path, local_path)

            if os.path.exists(local_path):
                with open(local_path, 'r', encoding='utf-8', errors='ignore') as f:
                    result_content = f.read()
                found_path = remote_path
                break
        except Exception as e:
            logging.debug(f"Could not copy from {remote_path}: {e}")

    try:
        shutil.rmtree(temp_dir)
    except:
        pass

    if result_content is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not find sample.txt file"
        }

    content_lower = result_content.lower()

    # Check for original content
    has_original = "original content" in content_lower or "line 2" in content_lower

    # Check for added line
    required_text = "this line was added by the agent"
    has_added_line = required_text in content_lower

    score = 0
    feedback_parts = []

    if has_original and has_added_line:
        score = 100
        feedback_parts.append("File correctly modified with new line")
    elif has_added_line:
        score = 80
        feedback_parts.append("New line added but original content may be missing")
    elif has_original:
        score = 30
        feedback_parts.append("Original content preserved but new line not added")
    else:
        score = 10
        feedback_parts.append("File exists but content is unexpected")

    feedback_parts.append(f"Content lines: {len(result_content.splitlines())}")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
